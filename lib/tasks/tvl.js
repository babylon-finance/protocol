const chalk = require('chalk');
const { task } = require('hardhat/config');
const { from, eth, formatNumber } = require('../helpers');

task('tvl').setAction(async (args, { getContract, ethers, getRapid }, runSuper) => {
  const [deployer, owner] = await ethers.getSigners();

  const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

  const babController = await getContract('BabController', 'BabControllerProxy', deployer);
  const priceOracle = await getContract('PriceOracle', undefined, deployer);
  const gardens = await babController.getGardens();

  const valuer = await getContract('GardenValuer', undefined, deployer);
  let tvl = from(0);
  let totalReturns = from(0);
  for (const garden of gardens) {
    const gardenContract = await ethers.getContractAt('Garden', garden);
    const gardenNAV = (await valuer.calculateGardenValuation(garden, DAI))
      .mul(await gardenContract.totalSupply())
      .div(eth());
    const pricePerToken = await priceOracle.connect(owner).getPrice(await gardenContract.reserveAsset(), DAI);
    const principal = (await gardenContract.principal()).mul(pricePerToken).div(eth());
    const gardenReturns = gardenNAV.sub(principal);
    tvl = tvl.add(gardenNAV);
    totalReturns = totalReturns.add(gardenReturns);
    console.log(`${await gardenContract.name()}`);
    console.log(`  Wealth Created: $${chalk.green(formatNumber(ethers.utils.formatUnits(gardenReturns, 'ether')))}`);
    console.log(`  TVL: $${chalk.cyan(formatNumber(ethers.utils.formatUnits(gardenNAV, 'ether')))}`);
  }
  console.log('Babylon Protocol');
  console.log(`  Wealth Created: $${chalk.green(formatNumber(ethers.utils.formatUnits(totalReturns, 'ether')))} 💰`);
  console.log(`  TVL: $${chalk.cyan(formatNumber(ethers.utils.formatUnits(tvl, 'ether')))} 🤑`);
});
