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

describe.only('rewards', function () {
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

  const gardenNum = 30;
  const strategyNum = 10;
  const depositNum = 2;

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
    await babController.connect(owner).enableBABLMiningProgram();
    await fund([signer1.address, signer2.address, signer3.address]);
    const reserveContract = await ethers.getContractAt(
      '@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20',
      addresses.tokens.WETH,
    );
  });

  async function withdraw(gardens) {
    for (const garden of gardens) {
      for (let signer of [signer1, signer2]) {
        await garden.connect(signer).withdraw(eth(2), eth(1), signer.getAddress(), false, ADDRESS_ZERO, {
          gasPrice: 0,
        });
        await increaseTime(3600);
      }
    }
  }
  async function claim(gardens) {
    for (const garden of gardens) {
      for (let signer of [signer1, signer2]) {
        await garden.connect(signer).claimReturns(await garden.getFinalizedStrategies());
        await increaseTime(3600);
      }
    }
  }

  async function finalize(strategies) {
    for (const strategy of strategies) {
      await strategy.connect(keeper).finalizeStrategy(0, '', { gasPrice: 0 });
      await increaseTime(3600);
    }
  }

  async function execute(strategies) {
    for (const strategy of strategies) {
      await strategy.connect(keeper).executeStrategy(STRATEGY_EXECUTE_MAP[addresses.tokens.WETH], 0, {
        gasPrice: 0,
      });
      await increaseTime(3600);
    }
  }

  async function create(gardens) {
    const strategies = [];
    for (const garden of gardens) {
      await increaseTime(3600);
      strategies.push(await getStrategy({ garden, state: 'vote', specificParams: [addresses.tokens.DAI, 0] }));
    }
    return strategies;
  }

  async function deposit(gardens) {
    const reserveContract = await ethers.getContractAt(
      '@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20',
      addresses.tokens.WETH,
    );
    for (const garden of gardens) {
      for (let signer of [signer1, signer2]) {
        await reserveContract.connect(signer).approve(garden.address, eth(9999999), { gasPrice: 0 });
        for (let j = 0; j < depositNum; j++) {
          await garden.connect(signer).deposit(eth(0.1), eth(0.1), signer.getAddress(), false, {});
          await increaseTime(3600);
        }
      }
    }
  }

  it('simulate mining rewards launch', async function () {
    const gardens = [];
    for (let i = 0; i < gardenNum; i++) {
      gardens.push(await createGarden({ params: [eth(1e4), ...GARDEN_PARAMS.slice(1)] }));
    }

    let strategies = [];
    for (let i = 0; i < strategyNum; i++) {
      const newStrategies = await create(gardens);

      await increaseTime(ONE_DAY_IN_SECONDS);
      await deposit(gardens);

      await increaseTime(ONE_DAY_IN_SECONDS);
      await execute(newStrategies);

      strategies = [...strategies, ...newStrategies];
    }

    await increaseTime(ONE_DAY_IN_SECONDS * 30);
    await finalize(strategies);

    await increaseTime(ONE_DAY_IN_SECONDS);
    await claim(gardens);

    await increaseTime(ONE_DAY_IN_SECONDS);
    await withdraw(gardens);
  });
});
