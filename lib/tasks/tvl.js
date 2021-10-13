const chalk = require('chalk');
const { task } = require('hardhat/config');
const { from, eth, formatNumber } = require('../helpers');

task('tvl').setAction(async (args, { getContract, ethers, getRapid }, runSuper) => {
  const [deployer, owner] = await ethers.getSigners();

  const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

  const babController = await getContract('BabController', 'BabControllerProxy', deployer);
  const priceOracle = await getContract('PriceOracle', undefined, deployer);
  const babViewer = await getContract('BabylonViewer', undefined, deployer);
  const gardens = await babController.getGardens();

  const valuer = await getContract('GardenValuer', undefined, deployer);
  let tvl = from(0);
  let totalWealth = from(0);
  for (const garden of gardens) {
    const gardenContract = await ethers.getContractAt('Garden', garden);
    const priceOfReserveAsset = await priceOracle.connect(owner).getPrice(await gardenContract.reserveAsset(), DAI);
    const strategies = await gardenContract.getStrategies();
    let expectedReturns = from(0);
    for (const strategy of strategies) {
      const strategyContract = await ethers.getContractAt('Strategy', strategy);
      const capitalAllocated = await strategyContract.capitalAllocated();
      const strategyNAV = await strategyContract.getNAV();
      expectedReturns = expectedReturns.add(strategyNAV.sub(capitalAllocated));
    }
    expectedReturns = expectedReturns.mul(priceOfReserveAsset).div(eth());
    const gardenNAV = (await valuer.calculateGardenValuation(garden, DAI))
      .mul(await gardenContract.totalSupply())
      .div(eth());
    const principal = (await babViewer.getGardenPrincipal(garden)).mul(priceOfReserveAsset).div(eth());
    tvl = tvl.add(gardenNAV);
    const absoluteReturns = (await gardenContract.absoluteReturns()).mul(priceOfReserveAsset).div(eth());
    const reserveAssetRewardsSetAside = (await gardenContract.reserveAssetRewardsSetAside())
      .mul(priceOfReserveAsset)
      .div(eth());
    const totalKeeperFees = (await gardenContract.totalKeeperFees()).mul(priceOfReserveAsset).div(eth());
    const wealthCreated = absoluteReturns.add(reserveAssetRewardsSetAside).sub(totalKeeperFees).add(expectedReturns);
    totalWealth = totalWealth.add(wealthCreated);
    console.log(`${await gardenContract.name()}`);
    console.log(
      `  Rewards: $${chalk.green(formatNumber(ethers.utils.formatUnits(reserveAssetRewardsSetAside, 'ether')))}`,
    );
    console.log(
      `  Absolute Returns: $${chalk.green(formatNumber(ethers.utils.formatUnits(absoluteReturns, 'ether')))}`,
    );
    console.log(
      `  Expected Returns: $${chalk.green(formatNumber(ethers.utils.formatUnits(expectedReturns, 'ether')))}`,
    );
    console.log(`  Total Keeper Fees: $${chalk.red(formatNumber(ethers.utils.formatUnits(totalKeeperFees, 'ether')))}`);
    console.log(`  Wealth Created: $${chalk.green(formatNumber(ethers.utils.formatUnits(wealthCreated, 'ether')))}`);
    console.log(`  TVL: $${chalk.cyan(formatNumber(ethers.utils.formatUnits(gardenNAV, 'ether')))}`);
  }
  console.log('Babylon Protocol');
  console.log(`  Wealth Created: $${chalk.green(formatNumber(ethers.utils.formatUnits(totalWealth, 'ether')))} 💰`);
  console.log(`  TVL: $${chalk.cyan(formatNumber(ethers.utils.formatUnits(tvl, 'ether')))} 🤑`);
});
