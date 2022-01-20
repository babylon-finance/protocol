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

  for (const garden of gardens) {
    const gardenContract = await ethers.getContractAt('Garden', garden);
    const gardenName = await gardenContract.name();
    const creator = await gardenContract.creator();
    console.log(`Garden ${chalk.green(gardenName)}`);
    console.log(`  Address ${garden}`);

    console.log('  Stuck Strategies');
    const strategies = await gardenContract.getStrategies();
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
  }
  console.log('Stuck strategies');
  console.log(stuck.join('\r\n'));
});
