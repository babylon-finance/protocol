const { ethers } = require('ethers');
const { task } = require('hardhat/config');
const chalk = require('chalk');
const { from, parse, eth, formatNumber } = require('../helpers');

task('stuck').setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
  const [deployer] = await ethers.getSigners();

  const block = await ethers.provider.getBlock();
  const now = block.timestamp;
  console.log('now', now);
  const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

  const babController = await getContract('BabController', 'BabControllerProxy', deployer);
  const strategyNft = await getContract('StrategyNFT', 'StrategyNFT', deployer);
  const gardens = await babController.getGardens();

  const stuck = [];
  const sweepPending = [];

  const stuckRewards = [
    '0xD533a949740bb3306d119CC777fa900bA034cd52', // Curve
    '0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B', // Convex
    '0xdBdb4d16EdA451D0503b854CF79D55697F90c8DF', // ALCX
    '0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32', // LDO
    '0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F', // SNX
  ];

  for (const garden of gardens) {
    const gardenContract = await ethers.getContractAt('Garden', garden);
    const gardenName = await gardenContract.name();
    const creator = await gardenContract.creator();
    console.log(`Garden ${chalk.green(gardenName)}`);
    console.log(`  Address ${garden}`);

    console.log('  Checking stuck Strategies');
    const strategies = await gardenContract.getStrategies();
    const finalizedStrategies = await gardenContract.getFinalizedStrategies();

    for (const strategy of strategies) {
      const name = await strategyNft.getStrategyName(strategy);

      const strategyContract = await ethers.getContractAt('Strategy', strategy);

      const [, active, , finalized, executedAt, ,] = await strategyContract.getStrategyState();

      const duration = await strategyContract.duration();

      if (!finalized && active && executedAt.gt(0) && executedAt.add(duration).lt(now)) {
        console.log(`    Strategy ${name} at ${strategy}`);
        stuck.push(strategy);
      }
    }
    console.log('  Checking stuck Rewards');

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
          // We are only interested if > 0 , not the value itself (i.e. decimals not relevant for now)
          stuckBalance = from(stuckBalance).add(rewardsBalance);
        }
        if (stuckBalance.gt(0)) {
          console.log(`    Strategy ${name} at ${strategy} has stuck rewards`, stuckBalance.toString());
          // We only add strategies with stuck rewards
          sweepPending.push(strategy);
        }
      }
    }
  }
  console.log('Stuck strategies');
  console.log(stuck.join('\r\n'));
  console.log('');
  console.log('Stuck rewards in finalized strategies');
  console.log(sweepPending.join('\r\n'));
});
