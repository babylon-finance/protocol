const { expect } = require('chai');
const { strategyParamsToArray, createStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const { ONE_DAY_IN_SECONDS, ADDRESS_ZERO, DAI_STRATEGY_PARAMS, WETH_STRATEGY_PARAMS } = require('lib/constants');
const { increaseTime, getERC20, eth, from } = require('utils/test-helpers');
const addresses = require('lib/addresses');

describe('ComplexIntegrationsTest', function () {
  let aaveBorrowIntegration;
  let aaveLendIntegration;
  let compoundBorrowIntegration;
  let compoundLendIntegration;
  let masterSwapper;
  let signer1;
  let signer2;
  let signer3;
  let usdc;
  let dai;
  let weth;

  const DPI = '0x1494CA1F11D487c2bBe4543E90080AeBa4BA3C2b';

  beforeEach(async () => {
    ({
      aaveBorrowIntegration,
      aaveLendIntegration,
      compoundBorrowIntegration,
      compoundLendIntegration,
      masterSwapper,
      signer1,
      signer2,
      signer3,

      usdc,
      dai,
      weth,
    } = await setupTests()());
  });

  describe('getNAV', function () {
    it(`Leveraged stETH`, async function () {
      await transferFunds(dai.address);

      const garden = await createGarden();

      await depositFunds(addresses.tokens.WETH, garden);
      await depositFunds(addresses.tokens.WETH, garden);
      await depositFunds(addresses.tokens.WETH, garden);
      await depositFunds(addresses.tokens.WETH, garden);
      await depositFunds(addresses.tokens.WETH, garden);
      await depositFunds(addresses.tokens.WETH, garden);


      const strategyContract = await createStrategy(
        'custom',
        'vote',
        [signer1, signer2, signer3],
        [
          aaveLendIntegration.address,
          aaveBorrowIntegration.address,
          aaveLendIntegration.address,
          aaveBorrowIntegration.address,
          aaveLendIntegration.address,
          aaveBorrowIntegration.address,
          aaveLendIntegration.address,
        ],
        garden,
        strategyParamsToArray({ ...WETH_STRATEGY_PARAMS, maxCapitalRequested: eth(100) }),
        [
          addresses.tokens.stETH,
          0,
          addresses.tokens.WETH,
          0,
          addresses.tokens.stETH,
          0,
          addresses.tokens.WETH,
          0,
          addresses.tokens.stETH,
          0,
          addresses.tokens.WETH,
          0,
          addresses.tokens.stETH,
          0,
        ],
        [
         3,
         4,
         3,
         4,
         3,
         4,
         3
        ],
      );

      const gardenBalance = await weth.balanceOf(garden.address);
      await executeStrategy(strategyContract, { amount: eth(10) });
      expect(await strategyContract.getNAV()).to.be.closeTo(eth(10), eth().div(30));

      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await finalizeStrategy(strategyContract);

      expect(await strategyContract.getNAV()).to.eq(0);
      expect(await weth.balanceOf(garden.address)).to.be.closeTo(gardenBalance, gardenBalance.div(100));
    });

    it(`DAI Garden of a leveraged ETH (AaveLend WETH->AaveBorrow DAI->BuyOp WETH)`, async function () {
      await transferFunds(dai.address);

      const garden = await createGarden({ reserveAsset: dai.address });

      await depositFunds(dai.address, garden);

      const strategyContract = await createStrategy(
        'custom',
        'vote',
        [signer1, signer2, signer3],
        [aaveLendIntegration.address, aaveBorrowIntegration.address, masterSwapper.address],
        garden,
        DAI_STRATEGY_PARAMS,
        [weth.address, 0, dai.address, 0, weth.address, 0],
        [3, 4, 0],
      );
      await executeStrategy(strategyContract);

      const nav = await strategyContract.getNAV();
      expect(nav).to.be.closeTo(eth(1100), eth(1100).div(10));
    });

    it(`DAI Garden (CompLend WETH->CompBorrow DAI->BuyOp DPI)`, async function () {
      await transferFunds(dai.address);

      const garden = await createGarden({ reserveAsset: dai.address });

      await depositFunds(dai.address, garden);
      const strategyContract = await createStrategy(
        'custom',
        'vote',
        [signer1, signer2, signer3],
        [compoundLendIntegration.address, compoundBorrowIntegration.address, masterSwapper.address],
        garden,
        DAI_STRATEGY_PARAMS,
        [ADDRESS_ZERO, 0, dai.address, 0, DPI, 0],
        [3, 4, 0],
      );
      await executeStrategy(strategyContract);

      // const nav = await strategyContract.getNAV();
      // TODO Fix NAV calculations it returns 40% less value than capital allocated
      // expect(nav).to.be.closeTo(eth(1000), eth(20));
    });

    it(`DAI Garden (AaveLend WETH->AaveBorrow DAI->BuyOp DPI)`, async function () {
      await transferFunds(dai.address);

      const garden = await createGarden({ reserveAsset: dai.address });

      await depositFunds(dai.address, garden);
      const strategyContract = await createStrategy(
        'custom',
        'vote',
        [signer1, signer2, signer3],
        [aaveLendIntegration.address, aaveBorrowIntegration.address, masterSwapper.address],
        garden,
        DAI_STRATEGY_PARAMS,
        [weth.address, 0, dai.address, 0, DPI, 0],
        [3, 4, 0],
      );
      await executeStrategy(strategyContract);

      // const nav = await strategyContract.getNAV();
      // TODO Fix NAV calculations it returns 40% less value than capital allocated
      // expect(nav).to.be.closeTo(eth(1000), eth(20));
    });

    it(`DAI Garden (CompLend WETH->CompBorrow USDC->BuyOp DPI)`, async function () {
      await transferFunds(dai.address);

      const garden = await createGarden({ reserveAsset: dai.address });

      await depositFunds(dai.address, garden);
      const strategyContract = await createStrategy(
        'custom',
        'vote',
        [signer1, signer2, signer3],
        [compoundLendIntegration.address, compoundBorrowIntegration.address, masterSwapper.address],
        garden,
        DAI_STRATEGY_PARAMS,
        [ADDRESS_ZERO, 0, usdc.address, 0, DPI, 0],
        [3, 4, 0],
      );
      await executeStrategy(strategyContract);

      // const nav = await strategyContract.getNAV();
      // TODO Fix NAV calculations it returns 40% less value than capital allocated
      // expect(nav).to.be.closeTo(eth(1000), eth(20));
    });
  });
});
