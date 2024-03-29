const chalk = require('chalk');
const { task } = require('hardhat/config');
const { from, eth, formatNumber, formatUnit } = require('../helpers');

task('tvl').setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
  const [deployer, owner] = await ethers.getSigners();

  const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

  const babController = await getContract('BabController', 'BabControllerProxy', deployer);
  const priceOracle = await getContract('PriceOracle', undefined, deployer);
  const viewer = await getContract('IViewer', 'Viewer', deployer);
  const gardens = await babController.getGardens();

  const valuer = await getContract('GardenValuer', undefined, deployer);
  let tvl = from(0);
  let totalWealth = from(0);
  for (const garden of gardens) {
    const gardenContract = await ethers.getContractAt('IGarden', garden);
    const priceOfReserveAsset = await priceOracle.connect(owner).getPrice(await gardenContract.reserveAsset(), DAI);
    const strategies = await gardenContract.getStrategies();
    const reserveAsset = await ethers.getContractAt(
      '@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20',
      await gardenContract.reserveAsset(),
    );

    const decimals = await reserveAsset.decimals();
    const decimalsDiff = 18 - decimals;
    let expectedReturns = from(0);
    for (const strategy of strategies) {
      const strategyContract = await ethers.getContractAt('Strategy', strategy);
      const capitalAllocated = await strategyContract.capitalAllocated();
      const strategyNAV = await strategyContract.getNAV();
      expectedReturns = expectedReturns.add(strategyNAV.sub(capitalAllocated));
    }
    expectedReturns = expectedReturns
      .mul(priceOfReserveAsset)
      .mul(10 ** decimalsDiff)
      .div(eth());
    const gardenNAV = (await valuer.calculateGardenValuation(garden, DAI))
      .mul(await gardenContract.totalSupply())
      .mul(10 ** decimalsDiff)
      .div(eth());
    const principal = (await viewer.getGardenPrincipal(garden)).mul(priceOfReserveAsset).div(eth());
    tvl = tvl.add(gardenNAV);
    const absoluteReturns = (await gardenContract.absoluteReturns())
      .mul(priceOfReserveAsset)
      .mul(10 ** decimalsDiff)
      .div(eth());
    const reserveAssetRewardsSetAside = (await gardenContract.reserveAssetRewardsSetAside())
      .mul(priceOfReserveAsset)
      .mul(10 ** decimalsDiff)
      .div(eth());
    const totalKeeperFees = (await gardenContract.totalKeeperFees())
      .mul(priceOfReserveAsset)
      .mul(10 ** decimalsDiff)
      .div(eth());
    const wealthCreated = absoluteReturns.add(reserveAssetRewardsSetAside).sub(totalKeeperFees).add(expectedReturns);
    totalWealth = totalWealth.add(wealthCreated);
    console.log(`${await gardenContract.name()}`);
    console.log(`  Rewards: $${chalk.green(formatUnit(reserveAssetRewardsSetAside))}`);
    console.log(`  Absolute Returns: $${chalk.green(formatUnit(absoluteReturns))}`);
    console.log(`  Expected Returns: $${chalk.green(formatUnit(expectedReturns))}`);
    console.log(`  Total Keeper Fees: $${chalk.red(formatUnit(totalKeeperFees))}`);
    console.log(`  Wealth Created: $${chalk.green(formatUnit(wealthCreated))}`);
    console.log(`  TVL: $${chalk.cyan(formatUnit(gardenNAV))}`);
  }
  console.log('Babylon Protocol');
  console.log(`  Wealth Created: $${chalk.green(formatUnit(totalWealth))} 💰`);
  console.log(`  TVL: $${chalk.cyan(formatUnit(tvl))} 🤑`);
});
