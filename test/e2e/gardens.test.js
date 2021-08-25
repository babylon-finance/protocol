const { expect } = require('chai');
const { ethers } = require('hardhat');

const addresses = require('lib/addresses');
const { fund } = require('lib/whale');
const {
  STRATEGY_EXECUTE_MAP,
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

describe.only('protocol', function () {
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

  it('create gardens', async function () {
    for (let i = 0; i < 1; i++) {
      const garden = await createGarden();
      const strategy = await getStrategy({ state: 'vote', specificParams: [addresses.tokens.DAI, 0] });

      await increaseTime(ONE_DAY_IN_SECONDS);
      await strategy.connect(keeper).executeStrategy(STRATEGY_EXECUTE_MAP[addresses.tokens.WETH], 0, {
        gasPrice: 0,
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 30);
      await strategy.connect(keeper).finalizeStrategy(0, '', { gasPrice: 0 });
    }
  });
});
