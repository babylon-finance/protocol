const { expect } = require('chai');
const { ethers } = require('hardhat');
const { createStrategy, executeStrategy, finalizeStrategy, DAI_STRATEGY_PARAMS } = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { from, eth, parse } = require('lib/helpers');

describe('ComplexIntegrationsTest', function () {
  let aaveBorrowIntegration;
  let aaveLendIntegration;
  let uniswapV3TradeIntegration;
  let compoundBorrowIntegration;
  let compoundLendIntegration;
  let signer1;
  let signer2;
  let signer3;
  let usdc;
  let dai;
  let weth;

  beforeEach(async () => {
    ({
      aaveBorrowIntegration,
      uniswapV3TradeIntegration,
      aaveLendIntegration,
      compoundBorrowIntegration,
      compoundLendIntegration,
      signer1,
      signer2,
      signer3,

      usdc,
      dai,
      weth,
    } = await setupTests()());
  });

  describe('getNAV', function () {
    it.only(`DAI Garden of a leveraged ETH (AaveLend WETH->AaveBorrow DAI->BuyOp WETH)`, async function () {
      await transferFunds(dai.address);

      const garden = await createGarden({ reserveAsset: dai.address });

      await depositFunds(dai.address, garden);

      const strategyContract = await createStrategy(
        'custom',
        'vote',
        [signer1, signer2, signer3],
        [aaveLendIntegration.address, aaveBorrowIntegration.address, uniswapV3TradeIntegration.address],
        garden,
        DAI_STRATEGY_PARAMS,
        [weth.address, 0, dai.address, 0, weth.address, 0],
        [3, 4, 0],
      );
      await executeStrategy(strategyContract);

      const nav = await strategyContract.getNAV();
      expect(nav).to.be.closeTo(eth(1000), eth(20));
    });
    it.only(`DAI Garden (CompLend WETH->CompBorrow USDC->BuyOp DPI)`, async function () {
      await transferFunds(dai.address);

      const garden = await createGarden({ reserveAsset: dai.address });

      await depositFunds(dai.address, garden);
      const DPI = '0x1494CA1F11D487c2bBe4543E90080AeBa4BA3C2b';
      console.log('Lend weth', weth.address.toString());
      console.log('Borrow usdc', usdc.address.toString());
      console.log('Buy DPI', DPI.toString());
      const strategyContract = await createStrategy(
        'custom',
        'vote',
        [signer1, signer2, signer3],
        [compoundLendIntegration.address, compoundBorrowIntegration.address, uniswapV3TradeIntegration.address],
        garden,
        DAI_STRATEGY_PARAMS,
        // [weth.address, 0, usdc.address, 0, DPI, 0],
        [weth.address, 0, dai.address, 0, DPI, 0],
        [3, 4, 0],
      );
      console.log('Strategy created');
      await executeStrategy(strategyContract);
      console.log('EXECUTED');
      // const nav = await strategyContract.getNAV();
      // expect(nav).to.be.closeTo(eth(1000), eth(20));
    });
    it.only(`DAI Garden (AaveLend WETH->AaveBorrow USDC->BuyOp DPI)`, async function () {
      await transferFunds(dai.address);

      const garden = await createGarden({ reserveAsset: dai.address });

      await depositFunds(dai.address, garden);
      const DPI = '0x1494CA1F11D487c2bBe4543E90080AeBa4BA3C2b';
      console.log('Lend weth', weth.address.toString());
      console.log('Borrow usdc', usdc.address.toString());
      console.log('Buy DPI', DPI.toString());
      const strategyContract = await createStrategy(
        'custom',
        'vote',
        [signer1, signer2, signer3],
        [aaveLendIntegration.address, aaveBorrowIntegration.address, uniswapV3TradeIntegration.address],
        garden,
        DAI_STRATEGY_PARAMS,
        // [weth.address, 0, usdc.address, 0, DPI, 0],
        [weth.address, 0, dai.address, 0, DPI, 0],
        [3, 4, 0],
      );
      console.log('Strategy created');
      await executeStrategy(strategyContract);
      console.log('EXECUTED');
      // const nav = await strategyContract.getNAV();
      // expect(nav).to.be.closeTo(eth(1000), eth(20));
    });
  });
});
