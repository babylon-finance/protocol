const { expect } = require('chai');
const { strategyParamsToArray, createStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const {
  getGardenParams,
  GARDEN_PARAMS,
  ONE_DAY_IN_SECONDS,
  ADDRESS_ZERO,
  DAI_STRATEGY_PARAMS,
  WETH_STRATEGY_PARAMS,
} = require('lib/constants');
const { formatNumber, formatUnit } = require('lib/helpers');
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

      const pool = new ethers.Contract(
        '0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9',
        [
          'function getUserAccountData(address user) external view returns ( uint256 totalCollateralETH, uint256 totalDebtETH, uint256 availableBorrowsETH, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor)',
        ],
        signer1,
      );

      const amount = eth(10);
      const stETH = await getERC20(addresses.tokens.stETH);

      const garden = await createGarden({ params: getGardenParams({ maxDepositLimit: amount.mul(10) }) });

      await depositFunds(addresses.tokens.WETH, garden, amount);

      const leverage = 7;

      const strategyContract = await createStrategy(
        'custom',
        'vote',
        [signer1, signer2, signer3],
        [
          ...[...Array(leverage).keys()]
            .map((item) => [aaveLendIntegration.address, aaveBorrowIntegration.address])
            .flat(),
          aaveLendIntegration.address,
        ],
        garden,
        strategyParamsToArray({ ...WETH_STRATEGY_PARAMS, maxCapitalRequested: amount }),
        [
          ...[...Array(leverage).keys()]
            .map((item) => [addresses.tokens.stETH, 0, addresses.tokens.WETH, eth()])
            .flat(),
          addresses.tokens.stETH,
          0,
        ],
        [...[...Array(leverage).keys()].map((item) => [3, 4]).flat(), 3],
      );

      const gardenBalance = await weth.balanceOf(garden.address);
      await executeStrategy(strategyContract, { amount });
      expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(100));
      const [
        totalCollateralETH,
        totalDebtETH,
        availableBorrowsETH,
        currentLiquidationThreshold,
        ltv,
        healthFactor,
      ] = await pool.getUserAccountData(strategyContract.address);

      console.log(`stETH balance: ${formatUnit(totalCollateralETH.toString())} ETH`);
      console.log(`leverage: x${formatUnit(totalCollateralETH.mul(eth()).div(amount))}`);

      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await finalizeStrategy(strategyContract);

      const newBalance = await weth.balanceOf(garden.address);
      console.log(`losses: ${eth().sub(newBalance.mul(eth()).div(gardenBalance))}%`);

      expect(await strategyContract.getNAV()).to.eq(0);
      expect(await weth.balanceOf(garden.address)).to.be.closeTo(gardenBalance, gardenBalance.div(30));
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
