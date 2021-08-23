const { expect } = require('chai');
const { ethers } = require('hardhat');

const addresses = require('lib/addresses');
const { fund } = require('lib/whale');
const {
  NOW,
  PROFIT_STRATEGIST_SHARE,
  PROFIT_STEWARD_SHARE,
  PROFIT_LP_SHARE,
  ONE_DAY_IN_SECONDS,
  PROTOCOL_FEE,
  PROFIT_PROTOCOL_FEE,
  GARDEN_PARAMS_STABLE,
  GARDEN_PARAMS,
  ADDRESS_ZERO,
} = require('lib/constants.js');
const { increaseTime } = require('utils/test-helpers');
const { from, eth, parse } = require('lib/helpers');
const { impersonateAddress } = require('lib/rpc');

const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  getStrategy,
  getStrategyState,
  executeStrategy,
  vote,
  finalizeStrategy,
  injectFakeProfits,
} = require('fixtures/StrategyHelper');

const { createGarden, getDepositSig, getWithdrawSig, transferFunds, depositFunds } = require('fixtures/GardenHelper');

const { setupTests } = require('fixtures/GardenFixture');

describe('gardens', function () {
  let babController;
  let rewardsDistributor;
  let owner;
  let keeper;
  let signer1;
  let signer2;
  let signer3;
  let garden1;
  let ishtarGate;
  let balancerIntegration;
  let uniswapV3TradeIntegration;
  let daiGarden;
  let usdcGarden;
  let gardenNFT;
  let gardenValuer;
  let babViewer;

  let usdc;
  let weth;
  let dai;
  let wbtc;

  beforeEach(async () => {
    ({
      babController,
      rewardsDistributor,
      gardenNFT,
      keeper,
      owner,
      signer1,
      signer2,
      signer3,
      garden1,
      ishtarGate,
      balancerIntegration,
      uniswapV3TradeIntegration,
      gardenValuer,
      babViewer,

      dai,
      usdc,
      weth,
      wbtc,
    } = await setupTests()());
  });

  describe('depositBySig', async function () {
    it('can deposit', async function () {
      const amountIn = from(1000 * 1e6);
      const minAmountOut = eth(1000);

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await usdc.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      const gardenBalance = await usdc.balanceOf(garden.address);
      const supplyBefore = await garden.totalSupply();

      const sig = await getDepositSig(garden.address, signer3, amountIn, minAmountOut, false, 0);
      await garden.connect(keeper).depositBySig(amountIn, minAmountOut, false, 0, eth(), sig.v, sig.r, sig.s);

      const supplyAfter = await garden.totalSupply();
      expect(supplyAfter.sub(supplyBefore)).to.be.eq(minAmountOut);

      const gardenBalanceAfter = await usdc.balanceOf(garden.address);
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(amountIn);
    });

    it('rejects wrong nonce', async function () {
      const amountIn = from(1000 * 1e6);
      const minAmountOut = eth(1000);

      await fund([signer1.address, signer3.address], [addresses.tokens.USDC]);

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await usdc.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      const sig = await getDepositSig(garden.address, signer3, amountIn, minAmountOut, false, 7);
      await expect(
        garden.connect(keeper).depositBySig(amountIn, minAmountOut, false, 7, eth(), sig.v, sig.r, sig.s),
      ).to.be.revertedWith('BAB#089');
    });
    // TODO: Test minAmountOut is respected
    // TODO: Test mintNFT is respected
  });
});
