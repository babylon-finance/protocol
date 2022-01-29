const { expect } = require('chai');
const { createStrategy, executeStrategy, DAI_STRATEGY_PARAMS } = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const { ADDRESS_ZERO } = require('lib/constants');
const { eth } = require('lib/helpers');

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
      expect(nav).to.be.closeTo(eth(1100), eth(1000).div(10));
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
