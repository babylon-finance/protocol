const { ethers } = require('ethers');
const { task } = require('hardhat/config');
const chalk = require('chalk');
const { from, parse, eth, formatNumber } = require('../helpers');

task('gardens').setAction(async (args, { getContract, ethers, getRapid }, runSuper) => {
  const [deployer] = await ethers.getSigners();

  const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

  const babController = await getContract('BabController', 'BabControllerProxy', deployer);
  const gardens = await babController.getGardens();

  const valuer = await getContract('GardenValuer', undefined, deployer);
  let tvl = from(0);
  for (const garden of gardens) {
    const gardenContract = await ethers.getContractAt('Garden', garden);
    const gardenName = await gardenContract.name();
    const gardenNAV = (await valuer.calculateGardenValuation(garden, DAI))
      .mul(await gardenContract.totalSupply())
      .div(eth());
    tvl = tvl.add(gardenNAV);
    console.log(`Garden ${chalk.green(gardenName)}`);
    console.log(`  Address ${garden}`);
    console.log(`  NAV $${chalk.green(formatNumber(ethers.utils.formatUnits(gardenNAV)))}`);

    console.log('  Strategies');
    const strategies = await gardenContract.getStrategies();
    for (const strategy of strategies) {
      const strategyContract = await ethers.getContractAt('Strategy', strategy);
      console.log(`    Strategy ${strategy}`);

      const finalized = await strategyContract.finalized();
      console.log('      finalized', finalized);

      const active = await strategyContract.active();
      console.log('      active', active);

      const isExecuting = await strategyContract.isStrategyActive();
      console.log('      isExecuting', isExecuting);

      const enteredAt = (await strategyContract.enteredAt()).toNumber();
      console.log('      enteredAt ', enteredAt);

      const enteredCooldownAt = (await strategyContract.enteredCooldownAt()).toNumber();
      console.log('      enteredCooldownAt', enteredCooldownAt);

      const executedAt = (await strategyContract.executedAt()).toNumber();
      console.log('      executedAt', executedAt);

      const duration = (await strategyContract.duration()).toNumber();
      console.log('      duration ', duration);

      const strategist = await strategyContract.strategist();
      console.log('      strategist', strategist);
      console.log();
    }

    console.log();
  }
});
