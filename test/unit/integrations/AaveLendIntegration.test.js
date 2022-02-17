const { expect } = require('chai');
const { ethers } = require('hardhat');
const {
  createStrategy,
  executeStrategy,
  finalizeStrategy,
  DEFAULT_STRATEGY_PARAMS,
  GARDENS,
} = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const addresses = require('lib/addresses');
const {
  pick,
  increaseTime,
  normalizeDecimals,
  getERC20,
  getContract,
  parse,
  from,
  eth,
} = require('utils/test-helpers');
const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');

describe('AaveLendIntegrationTest', function () {
  let aaveLendIntegration;
  let aaveBorrowIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let babController;
  let USDC;
  let WETH;
  let keeper;

  beforeEach(async () => {
    ({
      garden1,
      babController,
      aaveBorrowIntegration,
      aaveLendIntegration,
      signer1,
      signer2,
      signer3,
      keeper,
    } = await setupTests()());
    USDC = await getERC20(addresses.tokens.USDC);
    WETH = await getERC20(addresses.tokens.WETH);
  });

  describe('Aave Lend', function () {
    it('can supply to valid aToken', async function () {
      expect(await aaveLendIntegration.isInvestment(addresses.tokens.USDC)).to.equal(true);
    });

    it('gets the collateral factor of a token', async function () {
      expect(await aaveLendIntegration.getCollateralFactor('0x6b175474e89094c44da98b954eedeac495271d0f')).to.equal(
        ethers.utils.parseEther('0.80'),
      );
    });

    it('can supply and redeem tokens from Aave', async function () {
      const strategyContract = await createStrategy(
        'lend',
        'vote',
        [signer1, signer2, signer3],
        aaveLendIntegration.address,
        garden1,
      );

      await executeStrategy(strategyContract);
      expect(await USDC.balanceOf(strategyContract.address)).to.be.equal(0);
      const collateral = await aaveBorrowIntegration.getCollateralBalance(strategyContract.address, USDC.address);
      expect(collateral).to.be.gt(1);
      await finalizeStrategy(strategyContract);
      expect(await USDC.balanceOf(strategyContract.address)).to.equal(0);
      expect(await WETH.balanceOf(strategyContract.address)).to.equal(0);
      expect(await aaveBorrowIntegration.getCollateralBalance(strategyContract.address, USDC.address)).to.equal(0);
    });

    it('can supply the reserve asset (WETH)', async function () {
      const strategyContract = await createStrategy(
        'lend',
        'vote',
        [signer1, signer2, signer3],
        aaveLendIntegration.address,
        garden1,
        keeper,
        DEFAULT_STRATEGY_PARAMS,
        [WETH.address, 0],
      );

      await executeStrategy(strategyContract);
      expect(await WETH.balanceOf(strategyContract.address)).to.be.equal(0);
      const collateral = await aaveBorrowIntegration.getCollateralBalance(strategyContract.address, WETH.address);
      expect(collateral).to.be.gt(1);
      await finalizeStrategy(strategyContract);
      expect(await WETH.balanceOf(strategyContract.address)).to.equal(0);
      expect(await aaveBorrowIntegration.getCollateralBalance(strategyContract.address, WETH.address)).to.equal(0);
    });

    it('can supply and get NAV including rewards', async function () {
      const strategyContract = await createStrategy(
        'lend',
        'vote',
        [signer1, signer2, signer3],
        aaveLendIntegration.address,
        garden1,
        keeper,
        DEFAULT_STRATEGY_PARAMS,
        [WETH.address, 0],
      );
      await executeStrategy(strategyContract);
      expect(await WETH.balanceOf(strategyContract.address)).to.be.equal(0);
      increaseTime(ONE_DAY_IN_SECONDS);
      const NAV = await strategyContract.getNAV();
      const aaveAccrued = await aaveLendIntegration.getRewardsAccrued(strategyContract.address);
      expect(NAV.sub(aaveAccrued)).to.be.closeTo(eth('1'), eth('1').div(100));
    });
  });
});
