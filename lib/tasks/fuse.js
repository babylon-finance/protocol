const { ethers } = require('ethers');
const { task } = require('hardhat/config');
const chalk = require('chalk');
const { from, parse, eth, formatNumber, formatUnit } = require('../helpers');

const BABL = '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74';
const fBablMarket = '0x812EeDC9Eba9C428434fD3ce56156b4E23012Ebc';
const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
const HEART = '0x51e6775b7be2ea1d20ca02cfeeb04453366e72c8';

task('fuse')
  .addOptionalParam('log')
  .setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
    async function getFuseStatsForAddress({ address, comptroller, bablPrice, log }) {
      let totalDebt = from(0);
      let totalCollateral = from(0);
      let totalBorrow = from(0);

      const markets = await comptroller.getAssetsIn(address);

      for (const market of markets) {
        const [, collateralFactor] = await comptroller.markets(market);
        const fPool = await ethers.getContractAt('ICToken', market);

        const [, balance, borrow, exchangeRate] = await fPool.getAccountSnapshot(address);

        const collateral = balance.mul(exchangeRate).div(eth());

        const collateralInDAI = market === fBablMarket ? collateral.mul(bablPrice).div(eth()) : collateral;

        const maxBorrow = collateral.mul(collateralFactor).div(eth());

        const maxBorrowInDAI = collateralInDAI.mul(collateralFactor).div(eth());

        totalDebt = totalDebt.add(borrow);
        totalCollateral = totalCollateral.add(collateralInDAI);
        totalBorrow = totalBorrow.add(maxBorrowInDAI);

        if (log) {
          console.log(
            await new ethers.Contract(
              market,
              ['function name() external view returns (string memory)'],
              deployer,
            ).name(),
          );
          console.log(`balance ${formatUnit(balance)} fTokens`);
          console.log(`borrow ${formatUnit(borrow)}`);
          console.log('exchangeRate', formatUnit(exchangeRate));
          console.log('collateralFactor', formatUnit(collateralFactor));
          console.log('collateral', formatUnit(collateral));
          console.log(`collateralInDAI $${formatUnit(collateralInDAI)}`);
          console.log('maxBorrow', formatUnit(maxBorrow));
          console.log(`maxBorrowInDAI $${formatUnit(maxBorrowInDAI)}`);
          console.log('');
        }
      }

      console.log(`  Total Debt: $${formatUnit(totalDebt)}`);
      console.log(`  Total Collateral: $${formatUnit(totalCollateral)}`);
      console.log(`  Total Borrow: $${formatUnit(totalBorrow)}`);
      console.log(`  Borrow Limit: ${formatUnit(totalDebt.mul(eth()).div(totalBorrow).mul(100))}%`);
      console.log(
        `  Liquidation BABL Price: $${formatUnit(
          bablPrice.mul(eth()).div(eth().mul(eth()).div(totalDebt.mul(eth()).div(totalBorrow))),
        )}`,
      );
    }

    const { log } = args;
    const [deployer, owner] = await ethers.getSigners();

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
    const bablPrice = await priceOracle.getPrice(BABL, DAI);
    console.log(`BABL Price: $${formatUnit(bablPrice)}`);

    console.log(``);
    console.log(`Stats for HEART`);
    await getFuseStatsForAddress({ address: HEART, comptroller, bablPrice, log });
    console.log(``);

    console.log(`Stats for Heart Garden`);
    const strategyNft = await getContract('StrategyNFT', 'StrategyNFT', deployer);
    const heartGarden = await ethers.getContractAt('IGarden', '0xaA2D49A1d66A58B8DD0687E730FefC2823649791');
    const strategies = await heartGarden.getStrategies();
    for (const strategy of strategies) {
      const name = await strategyNft.getStrategyName(strategy);
      console.log(`  Strategy ${name} at ${strategy}`);
      await getFuseStatsForAddress({ address: strategy, comptroller, bablPrice, log });
    }
  });
