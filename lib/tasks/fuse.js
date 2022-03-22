const { ethers } = require('ethers');
const { task } = require('hardhat/config');
const chalk = require('chalk');
const { from, parse, eth, formatNumber, formatUnit } = require('../helpers');

task('fuse').setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
  const BABL = '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74';
  const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

  const priceOracle = await ethers.getContractAt('IPriceOracle', '0x28A619b28130A4aaf9236e7294d988A7ecD1A190');
  const comptroller = await ethers.getContractAt('IComptroller', '0xc7125e3a2925877c7371d579d29dae4729ac9033');
  const liquidity = await comptroller.getAccountLiquidity('0x51e6775b7be2ea1d20ca02cfeeb04453366e72c8');
  const cBABL = await ethers.getContractAt('ICToken', '0x812eedc9eba9c428434fd3ce56156b4e23012ebc');
  const bablPosition = await cBABL.getAccountSnapshot('0x51e6775b7be2ea1d20ca02cfeeb04453366e72c8');
  const cbablMarket = await comptroller.markets('0x812eedc9eba9c428434fd3ce56156b4e23012ebc');
  const cTokenBalance = bablPosition[1];
  const bablPrice = await priceOracle.getPrice(BABL, DAI);
  const bablCollateral = cTokenBalance.mul(bablPosition[3]).div(eth());
  const maxAmountsDaiBorrowable = bablCollateral.mul(bablPrice).div(eth()).mul(cbablMarket[1]).div(eth());

  console.log('babl Price', ethers.utils.formatEther(bablPrice));
  console.log('babl as collateral', ethers.utils.formatEther(bablCollateral));
  console.log('max amout dai borrowable', ethers.utils.formatEther(maxAmountsDaiBorrowable));
  console.log('liquidity', ethers.utils.formatEther(liquidity[1]));
});
