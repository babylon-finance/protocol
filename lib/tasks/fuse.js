const { ethers } = require('ethers');
const { task } = require('hardhat/config');
const chalk = require('chalk');
const { from, parse, eth, formatNumber, formatUnit } = require('../helpers');

const BABL = '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74';
const fBABLMarket = '0x812EeDC9Eba9C428434fD3ce56156b4E23012Ebc';
const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
const fDAIMarket = '0xA6C25548dF506d84Afd237225B5B34F2Feb1aa07';
const ETH = '0x0000000000000000000000000000000000000000';
const fETHMarket = '0x7DBC3aF9251756561Ce755fcC11c754184Af71F7';
const FEI = '0x956F47F50A910163D8BF957Cf5846D573E7f87CA';
const fFEIMarket = '0x3a2804ec0Ff521374aF654D8D0daA1d1aE1ee900';
const fFRAXMarket = '0xA54c548d11792b3d26aD74F5f899e12CDfD64Fd6';
const FRAX = '0x853d955acef822db058eb8505911ed77f175b99e';
const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
const HEART = '0x51e6775b7be2ea1d20ca02cfeeb04453366e72c8';
// const STUCK_STRATEGIES = ['0x7087Ea2702DC2932329BE4ef96CE4d5ed67102FF'];
const AFFECTED_GARDENS = [
  '0xB5bD20248cfe9480487CC0de0d72D0e19eE0AcB6', // Fountain of ETH
  '0x1D50c4F18D7af4fCe2Ea93c7942aae6260788596', // Stable Garden
  '0x3eeC6Ac8675ab1B4768f6032F0598e36Ac64f415', // Stable Peeble
  '0x99acDD18eb788E199be6Bf64d14142329316687a', // Waterfall2
  '0xa7D88c885209e953Eb66B238914a639cbbad94a8',
]; // Amplify Stables

let totalCollateralDAI;
let totalCollateralFEI;
let totalCollateralFRAX;
let totalCollateralETH;
let totalCollateralBABL;

const MIN_COLLATERAL = eth(1000);
const HEART_PREFIX = 'HEART';
const ACTIVE_STR_PREFIX = 'Strategy';
const FINALIZED_STR_PREFIX = 'Finalized Stuck Strategy';

task('fuse')
  .addOptionalParam('log')
  .setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
    async function getFuseStatsForAddress({ address, comptroller, log, prefix, name }) {
      let totalDebt = from(0);
      let totalCollateral = from(0);
      let totalBorrow = from(0);
      const ethPriceInDAI = await priceOracle.getPrice(WETH, DAI);
      const bablPrice = await priceOracle.getPrice(BABL, DAI);
      let collateralInBABL;
      let usesFuse;

      const markets = await comptroller.getAssetsIn(address);

      for (const market of markets) {
        const [, collateralFactor] = await comptroller.markets(market);
        const fPool = await ethers.getContractAt('ICToken', market);

        const [, balance, borrow, exchangeRate] = await fPool.getAccountSnapshot(address);

        if (balance.gt(0)) {
          usesFuse = true;
        }

        const collateral = balance.mul(exchangeRate).div(eth());

        const collateralInDAI =
          market === fBABLMarket
            ? collateral.mul(bablPrice).div(eth())
            : market === fETHMarket
            ? collateral.mul(ethPriceInDAI).div(eth())
            : collateral;

        if (market === fBABLMarket) {
          collateralInBABL = true;
        }

        const maxBorrow = collateral.mul(collateralFactor).div(eth());

        const maxBorrowInDAI = collateralInDAI.mul(collateralFactor).div(eth());

        totalDebt = totalDebt.add(borrow);
        totalCollateral = totalCollateral.add(collateralInDAI);
        totalBorrow = totalBorrow.add(maxBorrowInDAI);

        if (log && usesFuse) {
          console.log('');
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
      if (usesFuse && (totalCollateral.gt(MIN_COLLATERAL) || log)) {
        console.log('');
        console.log(`  ${prefix} ${name} at ${address}`);
        console.log(`  Total Debt: $${formatUnit(totalDebt)}`);
        console.log(`  Total Collateral: $${formatUnit(totalCollateral)}`);
        console.log(`  Max Borrow: $${formatUnit(totalBorrow)}`);
        console.log(
          `  Borrow Limit: ${totalBorrow.gt(0) ? formatUnit(totalDebt.mul(eth()).div(totalBorrow).mul(100)) : 0}%`,
        );
        if (totalDebt.gt(0) && collateralInBABL) {
          console.log(
            `  Liquidation BABL Price: $${
              totalBorrow.gt(0)
                ? formatUnit(bablPrice.mul(eth()).div(eth().mul(eth()).div(totalDebt.mul(eth()).div(totalBorrow))))
                : '--'
            }`,
          );
        }
      }
    }

    async function getTotalSupply({ comptroller }) {
      const markets = await comptroller.getAllMarkets();
      console.log(``);
      console.log(`Stats for Fuse Pool 144 Underlying Collateral`);
      console.log('');
      for (const market of markets) {
        const fPool = await ethers.getContractAt('ICToken', market);
        let token;
        let balance;
        if (market.toString() === fBABLMarket.toString()) {
          totalCollateralBABL = await fPool.getCash();
          token = await ethers.getContractAt('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20', BABL);
          balance = await token.balanceOf(fBABLMarket);
          console.log(`Balance ${formatUnit(totalCollateralBABL)} BABL`);
          // console.log(`Balance check ${formatUnit(totalCollateralBABL)} BABL (Balance ${formatUnit(balance)})`);
        } else if (market.toString() === fDAIMarket.toString()) {
          totalCollateralDAI = await fPool.getCash();
          token = await ethers.getContractAt('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20', DAI);
          balance = await token.balanceOf(fDAIMarket);
          console.log(`Balance ${formatUnit(totalCollateralDAI)} DAI`);
          // console.log(`Balance check ${formatUnit(totalCollateralDAI)} DAI (Balance ${formatUnit(balance)})`);
        } else if (market.toString() === fETHMarket.toString()) {
          totalCollateralETH = await fPool.getCash();
          balance = await ethers.provider.getBalance(fETHMarket);
          console.log(`Balance ${formatUnit(totalCollateralETH)} ETH`);
          // console.log(`Balance check ${formatUnit(totalCollateralETH)} ETH (Balance ${formatUnit(balance)})`);
        } else if (market.toString() === fFRAXMarket.toString()) {
          totalCollateralFRAX = await fPool.getCash();
          token = await ethers.getContractAt('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20', FRAX);
          balance = await token.balanceOf(fFRAXMarket);
          console.log(`Balance ${formatUnit(totalCollateralFRAX)} FRAX`);
          // console.log(`Balance check ${formatUnit(totalCollateralFRAX)} FRAX (Balance ${formatUnit(balance)})`);
        } else if (market.toString() === fFEIMarket.toString()) {
          totalCollateralFEI = await fPool.getCash();
          token = await ethers.getContractAt('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20', FEI);
          balance = await token.balanceOf(fFEIMarket);
          console.log(`Balance ${formatUnit(totalCollateralFEI)} FEI`);
          // console.log(`Balance check ${formatUnit(totalCollateralFEI)} FEI (Balance ${formatUnit(balance)})`);
        }
      }
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
    const babController = await getContract('BabController', 'BabControllerProxy', deployer);
    const gardens = await babController.getGardens();
    const bablPrice = await priceOracle.getPrice(BABL, DAI);
    console.log(`BABL Price: $${formatUnit(bablPrice)}`);

    console.log(``);
    console.log(`Stats for HEART`);
    let name = '';
    await getFuseStatsForAddress({ address: HEART, comptroller, log, prefix: HEART_PREFIX, name });
    console.log(``);

    console.log(`Stats for Heart Garden`);
    let strategyNft = await getContract('StrategyNFT', 'StrategyNFT', deployer);
    const heartGarden = await ethers.getContractAt('IGarden', '0xaA2D49A1d66A58B8DD0687E730FefC2823649791');
    let strategies = await heartGarden.getStrategies();
    let finalizedStrategies = await heartGarden.getFinalizedStrategies();

    for (const strategy of strategies) {
      const name = await strategyNft.getStrategyName(strategy);
      await getFuseStatsForAddress({ address: strategy, comptroller, log, prefix: ACTIVE_STR_PREFIX, name });
    }
    for (const strategy of finalizedStrategies) {
      const name = await strategyNft.getStrategyName(strategy);
      await getFuseStatsForAddress({
        address: strategy,
        comptroller,
        log,
        prefix: FINALIZED_STR_PREFIX,
        name,
      });
    }

    /*  // Check all gardens one by one 
      for (const garden of gardens) {
      const gardenContract = await ethers.getContractAt('IGarden', garden);
      console.log('');
      console.log(`Stats for garden`, (await gardenContract.name()));
      strategyNft = await getContract('StrategyNFT', 'StrategyNFT', deployer);
      strategies = await gardenContract.getStrategies();
      finalizedStrategies = await gardenContract.getFinalizedStrategies();
  
      for (const strategy of strategies) {
        const name = await strategyNft.getStrategyName(strategy);
        await getFuseStatsForAddress({ address: strategy, comptroller, log, prefix: ACTIVE_STR_PREFIX, name });
      }
    } */

    // Check only affected gardens
    for (const garden of AFFECTED_GARDENS) {
      const gardenContract = await ethers.getContractAt('IGarden', garden);
      console.log('');
      console.log(`Stats for garden`, await gardenContract.name());
      strategyNft = await getContract('StrategyNFT', 'StrategyNFT', deployer);
      strategies = await gardenContract.getStrategies();
      finalizedStrategies = await gardenContract.getFinalizedStrategies();

      for (const strategy of strategies) {
        const name = await strategyNft.getStrategyName(strategy);
        await getFuseStatsForAddress({ address: strategy, comptroller, log, prefix: ACTIVE_STR_PREFIX, name });
      }
    }

    // Calculate total supply of underlying
    await getTotalSupply({ comptroller });
    console.log('');
  });
