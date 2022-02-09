const { ethers } = require('ethers');
const { task } = require('hardhat/config');
const chalk = require('chalk');
const { from, parse, eth, formatNumber, formatUnit } = require('../helpers');

task('stuck').setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
  const [deployer] = await ethers.getSigners();

  const block = await ethers.provider.getBlock();
  const now = block.timestamp;
  console.log('now', now);
  const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

  const babController = await getContract('BabController', 'BabControllerProxy', deployer);
  const strategyNft = await getContract('StrategyNFT', 'StrategyNFT', deployer);
  const priceOracle = await getContract('PriceOracle', undefined, deployer);
  const gardens = await babController.getGardens();
  let totalStuckRewards = from(0);
  let capitalAllocatedStuck = from(0);

  const stuckToFinalize = [];
  const stuckToExecute = [];
  const sweepPending = [];

  const stuckRewards = [
    '0xD533a949740bb3306d119CC777fa900bA034cd52', // Curve 18 decimals
    '0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B', // Convex 18 decimals
    '0xdBdb4d16EdA451D0503b854CF79D55697F90c8DF', // ALCX 18 decimals
    '0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32', // LDO 18 decimals
    '0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F', // SNX 18 decimals
    '0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9', // AAVE 18 decimals
    '0xc00e94Cb662C3520282E6f5717214004A7f26888', // COMP 18 decimals
  ];

  for (const garden of gardens) {
    const gardenContract = await ethers.getContractAt('Garden', garden);
    const gardenName = await gardenContract.name();
    const creator = await gardenContract.creator();
    console.log(`Garden ${chalk.green(gardenName)}`);
    console.log(`  Address ${garden}`);

    console.log('  Checking stuck Strategies...');
    const strategies = await gardenContract.getStrategies();
    const finalizedStrategies = await gardenContract.getFinalizedStrategies();
    const cooldownPeriod = await gardenContract.strategyCooldownPeriod();
    const priceOfReserveAsset = await priceOracle.connect(deployer).getPrice(await gardenContract.reserveAsset(), DAI);

    for (const strategy of strategies) {
      const name = await strategyNft.getStrategyName(strategy);

      const strategyContract = await ethers.getContractAt('Strategy', strategy);

      const [, active, , finalized, executedAt, ,] = await strategyContract.getStrategyState();

      const enteredCoolDownAt = await strategyContract.enteredCooldownAt();

      const duration = await strategyContract.duration();

      if (!finalized && active && executedAt.gt(0) && executedAt.add(duration).lt(now)) {
        stuckToFinalize.push(strategy);
        const capitalAllocated = await strategyContract.capitalAllocated();
        // Normalize into DAI
        const allocatedNormalizedInDAI = capitalAllocated.mul(priceOfReserveAsset).mul(eth()).div(eth()).div(eth());
        capitalAllocatedStuck = from(capitalAllocatedStuck).add(allocatedNormalizedInDAI);
        // Stuck to be finalized
        console.log(
          `    Strategy ${name} at ${strategy} is ${chalk.red('stuck to finalize')} $${chalk.red(
            allocatedNormalizedInDAI.toString(),
          )}`,
        );
      } else if (
        active &&
        executedAt.eq(0) &&
        enteredCoolDownAt.gt(0) &&
        enteredCoolDownAt.add(cooldownPeriod).lt(now)
      ) {
        // Stuck to be executed
        console.log(`    Strategy ${name} at ${strategy} is ${chalk.yellow('stuck to execute')}`);
        stuckToExecute.push(strategy);
      }
    }
    console.log('  Checking stuck Rewards...');

    for (const strategy of finalizedStrategies) {
      const name = await strategyNft.getStrategyName(strategy);

      const strategyContract = await ethers.getContractAt('Strategy', strategy);

      const [, , , , , exitedAt] = await strategyContract.getStrategyState();

      if (exitedAt.gt(0)) {
        // we check if any stuck token is still there to be swept
        let stuckBalance = from(0);
        for (const token of stuckRewards) {
          const erc20 = await ethers.getContractAt('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20', token);
          const rewardsBalance = await erc20.balanceOf(strategy);
          if (rewardsBalance.gt(0)) {
            // We normalize balance into DAI
            const priceOfToken = await priceOracle.connect(deployer).getPrice(erc20.address, DAI);
            const rewardsNormalizedInDAI = rewardsBalance.mul(priceOfToken).mul(eth()).div(eth()).div(eth());
            stuckBalance = from(stuckBalance).add(rewardsNormalizedInDAI);
            totalStuckRewards = from(totalStuckRewards).add(stuckBalance);
          }
        }
        if (stuckBalance.gt(0)) {
          console.log(
            `    Strategy ${name} at ${strategy} has stuck rewards of total value $${chalk.blue(
              formatUnit(stuckBalance.toString()),
            )}`,
          );
          // We only add strategies with stuck rewards
          sweepPending.push(strategy);
        }
      }
    }
  }
  console.log('');
  console.log(
    `List of ${chalk.red('stuck strategies to finalize')} TVL $${chalk.red(capitalAllocatedStuck.toString())}`,
  );
  console.log(stuckToFinalize.join('\r\n'));
  console.log('');
  console.log(`List of ${chalk.yellow('stuck strategies to execute')}`);
  console.log(stuckToExecute.join('\r\n'));
  console.log('');
  console.log(
    `List of stuck rewards on finalized strategies - total stuck value $${chalk.blue(
      formatUnit(totalStuckRewards.toString()),
    )}`,
  );
  console.log(sweepPending.join('\r\n'));
});
