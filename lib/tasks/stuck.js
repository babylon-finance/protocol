const { ethers } = require('ethers');
const { task } = require('hardhat/config');
const chalk = require('chalk');
const { from, parse, eth, formatNumber, formatUnit } = require('../helpers');

const STUCK_STRATEGIES = [
  '0x64e257bf6ac9b390fe7452181ea233362a9c2995', // ATG
  '0x9303D3281B0D3956ebFF031f0b5910A188ef891b', // ETH + WBTC Arkad
  '0x5C0aFc3BFab3492baA1fC2F3C02355df7915398f', // Leverage long stETH Arkad
  '0xC483aFE1F252a4f8C02cE21a11A551Cf37A22852', // Leverage long dpi Arkad
  '0xc38E5828c1c84F4687f2080c0C8d2e4a89695A11', // long eth, borrow dai, steth crv convex
  '0x7AC096D32eAC2464962103238b89370003b8e108', // Spell long arkad
  '0x628c3134915D3d8c5073Ed8F618BCE1631b82416', // axs long arkad
  '0x8452baC761D9f78AA2aC450C1e7F3980Ca0C0785', // long BABL arkad
  '0x9991D647A35810023A1CDAdD8cE27C5F3a222e7d', // AAVE; long; arkad;
  '0x6F854a988577Ce994926a8979881E6a18E6a70dF', // red pill
  '0x11b1f3C622B129212D257d603D312244820cC367', // Rari exploit
  '0x69B9a89083E2324079922e01557cAfb87cd90B09', // Rari exploit
  '0x2d160210011a992966221F428f63326f76066Ba9', // Rari exploit
];

function checkIfPausedAtKeeper(strategy) {
  let found = false;
  for (const stuckStrategy of STUCK_STRATEGIES) {
    if (stuckStrategy === strategy) {
      found = true;
    }
  }
  return found;
}

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
  let capitalAllocatedStuckPaused = from(0);

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
    const gardenContract = await ethers.getContractAt('IGarden', garden);
    const gardenName = await gardenContract.name();
    const creator = await gardenContract.creator();
    const reserveAsset = await ethers.getContractAt(
      '@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20',
      await gardenContract.reserveAsset(),
    );

    const decimals = await reserveAsset.decimals();
    const decimalsDiff = 18 - decimals;
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
        const capitalAllocated = await strategyContract.capitalAllocated();
        // Normalize into DAI
        const allocatedNormalizedInDAI = capitalAllocated
          .mul(priceOfReserveAsset)
          .mul(10 ** decimalsDiff)
          .mul(eth())
          .div(eth())
          .div(eth());
        // Stuck to be finalized
        if (checkIfPausedAtKeeper(strategy)) {
          console.log(
            `    Strategy ${name} at ${strategy} is ${chalk.red('paused at keeper - locked capital')} $${chalk.red(
              formatUnit(allocatedNormalizedInDAI.toString()),
            )}`,
          );
          capitalAllocatedStuckPaused = from(capitalAllocatedStuckPaused).add(allocatedNormalizedInDAI);
        } else {
          console.log(
            `    Strategy ${name} at ${strategy} is ${chalk.red('stuck to finalize - locked capital')} $${chalk.red(
              formatUnit(allocatedNormalizedInDAI.toString()),
            )}`,
          );
          capitalAllocatedStuck = from(capitalAllocatedStuck).add(allocatedNormalizedInDAI);
          stuckToFinalize.push(strategy);
        }
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
            `    Strategy ${name} at ${strategy} has ${chalk.blue('stuck rewards')} of total value $${chalk.blue(
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
    `List of ${chalk.red('stuck strategies to finalize')} value $${chalk.red(
      formatUnit(capitalAllocatedStuck.toString()),
    )}`,
  );
  console.log(stuckToFinalize.join('\r\n'));
  console.log('');
  console.log('');
  console.log(
    `List of ${chalk.red('paused strategies to finalize')} value $${chalk.red(
      formatUnit(capitalAllocatedStuckPaused.toString()),
    )}`,
  );
  console.log(STUCK_STRATEGIES.join('\r\n'));
  console.log('');
  console.log(`List of ${chalk.yellow('stuck strategies to execute')}`);
  console.log(stuckToExecute.join('\r\n'));
  console.log('');
  console.log(
    `List of ${chalk.blue('stuck rewards on finalized strategies')} value $${chalk.blue(
      formatUnit(totalStuckRewards.toString()),
    )}`,
  );
  console.log(sweepPending.join('\r\n'));
});
