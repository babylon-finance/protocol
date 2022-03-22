const { ethers } = require('ethers');
const { task } = require('hardhat/config');
const chalk = require('chalk');
const { from, parse, eth, formatNumber, formatUnit } = require('../helpers');

task('fuse').setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
  const [deployer, owner] = await ethers.getSigners();

  const BABL = '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74';
  const fBablMarket = '0x812EeDC9Eba9C428434fD3ce56156b4E23012Ebc';
  const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
  const HEART = '0x51e6775b7be2ea1d20ca02cfeeb04453366e72c8';

  const fuseLens = new ethers.Contract(
    '0x6Dc585Ad66A10214Ef0502492B0CC02F0e836eec',
    [
      'function getUserSummary(address account) returns (uint256, uint256, bool)',
      'function getPoolSummary(address comptroller) returns (uint256, uint256, address[], string[])',
    ],
    deployer,
  );

  const priceOracle = await ethers.getContractAt('IPriceOracle', '0x28A619b28130A4aaf9236e7294d988A7ecD1A190');
  const comptroller = await ethers.getContractAt('IComptroller', '0xc7125e3a2925877c7371d579d29dae4729ac9033');
  // @return Tuple of values (error, liquidity, shortfall).  non-zero liquidity value indicates the account has available account liquidity.
  const liquidity = await comptroller.getAccountLiquidity(HEART);
  // @return (possible error, token balance, borrow balance, exchange rate mantissa)
  const bablPosition = await (await ethers.getContractAt('ICToken', fBablMarket)).getAccountSnapshot(HEART);
  // @return collateralFactorMantissa, scaled by 1e18, is multiplied by a supply balance to determine how much value can be borrowed.
  const fBablMarketInfo = await comptroller.markets(fBablMarket);
  const fBablBalance = bablPosition[1];
  const borrowBalance = bablPosition[2];
  const bablPrice = await priceOracle.getPrice(BABL, DAI);
  const bablCollateral = fBablBalance.mul(bablPosition[3]).div(eth());
  const maxAmountsDaiBorrowable = bablCollateral.mul(bablPrice).div(eth()).mul(fBablMarketInfo[1]).div(eth());
  const markets = await comptroller.getAssetsIn(HEART);
  const summary = await fuseLens.callStatic.getUserSummary(HEART);

  let totalDebt = from(0);
  let totalCollateral = from(0);
  let totalBorrow = from(0);
  for (const market of markets) {
    const [, collateralFactor] = await comptroller.markets(market);
    const fPool = await ethers.getContractAt('ICToken', market);
    console.log(
      await new ethers.Contract(market, ['function name() external view returns (string memory)'], deployer).name(),
    );

    const [, balance, borrow, exchangeRate] = await fPool.getAccountSnapshot(HEART);
    console.log(`balance ${formatUnit(balance)} fTokens`);
    console.log(`borrow ${formatUnit(borrow)}`);
    console.log('exchangeRate', formatUnit(exchangeRate));
    console.log('collateralFactor', formatUnit(collateralFactor));

    const collateral = balance.mul(exchangeRate).div(eth());
    console.log('collateral', formatUnit(collateral));

    const collateralInDAI = market === fBablMarket ? collateral.mul(bablPrice).div(eth()) : collateral;
    console.log(`collateralInDAI $${formatUnit(collateralInDAI)}`);

    const maxBorrow = collateral.mul(collateralFactor).div(eth());
    console.log('maxBorrow', formatUnit(maxBorrow));

    const maxBorrowInDAI = collateralInDAI.mul(collateralFactor).div(eth());
    console.log(`maxBorrowInDAI $${formatUnit(maxBorrowInDAI)}`);

    console.log('');

    totalDebt = totalDebt.add(borrow);
    totalCollateral = totalCollateral.add(collateralInDAI);
    totalBorrow = totalBorrow.add(maxBorrowInDAI);
  }

  console.log(`BABL Price: $${formatUnit(bablPrice)}`);
  console.log(`Total Debt: $${formatUnit(totalDebt)}`);
  console.log(`Total Collateral: $${formatUnit(totalCollateral)}`);
  console.log(`Total Borrow: $${formatUnit(totalBorrow)}`);
  console.log(`Borrow Limit: ${formatUnit(totalDebt.mul(eth()).div(totalBorrow).mul(100))}%`);
  console.log('');
});
