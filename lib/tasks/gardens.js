const { ethers } = require('ethers');
const { task } = require('hardhat/config');
const chalk = require('chalk');
const { from, parse, eth, formatNumber } = require('../helpers');

task('gardens').setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
  const [deployer] = await ethers.getSigners();

  const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

  const babController = await getContract('BabController', 'BabControllerProxy', deployer);
  const strategyNft = await getContract('StrategyNFT', 'StrategyNFT', deployer);
  const gardens = await babController.getGardens();

  const valuer = await getContract('GardenValuer', undefined, deployer);
  let tvl = from(0);
  for (const garden of gardens) {
    const gardenContract = await ethers.getContractAt('IGarden', garden);
    const gardenName = await gardenContract.name();
    const creator = await gardenContract.creator();
    const reserveAsset = await gardenContract.reserveAsset();
    const gardenNAV = (await valuer.calculateGardenValuation(garden, DAI))
      .mul(await gardenContract.totalSupply())
      .div(eth());
    tvl = tvl.add(gardenNAV);
    console.log(`Garden ${chalk.green(gardenName)}`);
    console.log(`  Address ${garden}`);
    console.log(`  Gardener ${creator}`);
    console.log(`  ReserveAsset $${reserveAsset}`);
    console.log(`  NAV $${chalk.green(formatNumber(ethers.utils.formatUnits(gardenNAV)))}`);

    console.log('  Strategies');
    const strategies = await gardenContract.getStrategies();
    for (const strategy of strategies) {
      const name = await strategyNft.getStrategyName(strategy);
      console.log(`    Strategy ${name} at ${strategy}`);

      const strategyContract = await ethers.getContractAt('Strategy', strategy);

      const [, active, , finalized, executedAt, ,] = await strategyContract.getStrategyState();
      const [
        ,
        ,
        ops,
        stake,
        totalPositiveVotes,
        totalNegativeVotes,
        capitalAllocated,
        capitalReturned,
        ,
        expectedReturn,
        maxCapitalRequested,
        ,
        ,
        NAV,
      ] = await strategyContract.getStrategyDetails();

      const maxAllocationPercentage = await strategyContract.maxAllocationPercentage();

      console.log('      capitalAllocated', formatNumber(ethers.utils.formatUnits(capitalAllocated)));

      console.log('      maxCapitalRequested', formatNumber(ethers.utils.formatUnits(maxCapitalRequested)));

      console.log(`      maxAllocationPercentage ${maxAllocationPercentage.div(eth(0.01)).toString()}%`);

      console.log('      finalized', finalized);

      console.log('      active', active);

      const isExecuting = await strategyContract.isStrategyActive();
      console.log('      isExecuting', isExecuting);

      const enteredAt = (await strategyContract.enteredAt()).toNumber();
      console.log('      enteredAt ', enteredAt);

      const enteredCooldownAt = (await strategyContract.enteredCooldownAt()).toNumber();
      console.log('      enteredCooldownAt', enteredCooldownAt);

      console.log('      executedAt', executedAt.toString());

      const duration = (await strategyContract.duration()).toNumber();
      console.log('      duration ', duration);

      const strategist = await strategyContract.strategist();
      console.log('      strategist', strategist);
      console.log();
    }

    console.log();
  }
});
