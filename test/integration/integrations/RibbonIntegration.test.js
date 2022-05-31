const { expect } = require('chai');
const { ethers } = require('hardhat');
const {
  createStrategy,
  getStrategy,
  executeStrategy,
  finalizeStrategy,
  signalUnlockStrategy,
  strategyParamsToArray,
} = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { increaseTime, getERC20, pick } = require('utils/test-helpers');
const {
  GARDENS,
  STRATEGY_EXECUTE_MAP,
  ADDRESS_ZERO,
  ONE_DAY_IN_SECONDS,
  STRATEGY_PARAMS_MAP,
} = require('lib/constants');

describe('RibbonIntegration', function () {
  let ribbonIntegration;
  let signer1;
  let signer2;
  let signer3;

  beforeEach(async () => {
    ({ ribbonIntegration, signer1, signer2, signer3 } = await setupTests()());
    // logAladdinPools();
  });

  describe('Ribbon Vault', function () {
    pick(GARDENS).forEach(async ({ token, name }) => {
      pick(addresses.ribbon.vault).forEach((pool) => {
        it(`can enter into convex ${pool.name} from a ${name} garden`, async function () {
          await depositIntoRibbon(pool.address, token, pool);
        });
      });
    });

    it(`cannot enter an invalid aladdin pool`, async function () {
      await expect(tryDepositIntoRibbon(ADDRESS_ZERO, addresses.tokens.WETH)).to.be.reverted;
    });
  });

  async function depositIntoRibbon(poolAddress, token, poolObj) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    const gardenReserveAsset = await getERC20(token);
    await depositFunds(token, garden);

    const integrations = ribbonIntegration.address;
    const params = [poolAddress, 0];
    const strategyKind = 'vault';
    const ops = [2];

    const strategyParams = strategyParamsToArray(STRATEGY_PARAMS_MAP[token]);
    strategyParams.strategyDuration = ONE_DAY_IN_SECONDS * (7 * 17 + 3);

    const strategyContract = await createStrategy(
      strategyKind,
      'vote',
      [signer1, signer2, signer3],
      integrations,
      garden,
      strategyParams,
      params,
      ops,
    );

    const amount = STRATEGY_EXECUTE_MAP[token];
    const balanceBeforeExecuting = await gardenReserveAsset.balanceOf(garden.address);

    await executeStrategy(strategyContract, { amount });
    // Check NAV
    const nav = await strategyContract.getNAV();
    expect(nav).to.be.closeTo(amount, amount.div(30));

    // Check reward after some time
    await increaseTime(ONE_DAY_IN_SECONDS * 2);

    expect(await strategyContract.getNAV()).to.be.gte(nav.sub(nav.div(100)));

    // Unstake
    await signalUnlockStrategy(strategyContract);
    await increaseTime(ONE_DAY_IN_SECONDS * 30);

    // Initiate withdraw
    await signalUnlockStrategy(strategyContract);
    await increaseTime(ONE_DAY_IN_SECONDS);
    // const cvxLocker = await ethers.getContractAt('ICleverCVXLocker', '0x96C68D861aDa016Ed98c30C810879F9df7c64154');
    // await cvxLocker.connect(signer1).harvest(strategyContract.address, 1);

    const balanceBeforeExiting = await gardenReserveAsset.balanceOf(garden.address);
    await finalizeStrategy(strategyContract, { gasLimit: 99900000 });

    expect(await strategyContract.getNAV()).to.eq(0);

    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.gte(balanceBeforeExiting);
    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.closeTo(
      balanceBeforeExecuting,
      balanceBeforeExecuting.div(10),
    );
  }

  async function tryDepositIntoRibbon(poolAddress, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    await depositFunds(token, garden);
    const strategyContract = await getStrategy({
      kind: 'vault',
      state: 'vote',
      integrations: ribbonIntegration.address,
      garden,
      specificParams: [poolAddress, 0],
    });

    await executeStrategy(strategyContract, { amount: STRATEGY_EXECUTE_MAP[token] });
  }
});
