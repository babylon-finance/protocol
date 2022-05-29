const { expect } = require('chai');
const { ethers } = require('hardhat');
const {
  createStrategy,
  getStrategy,
  executeStrategy,
  finalizeStrategy,
  signalUnlockStrategy,
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

describe('AladdinConcentratorIntegration', function () {
  let aladdinConcentratorIntegration;
  let curvePoolIntegration;
  let signer1;
  let signer2;
  let signer3;

  beforeEach(async () => {
    ({ curvePoolIntegration, aladdinConcentratorIntegration, signer1, signer2, signer3 } = await setupTests()());
    // logAladdinPools();
  });

  // Used to create addresses info. do not remove
  // async function logAladdinPools() {
  //   const aladdinConvexVault = await ethers.getContractAt(
  //     'IAladdinConvexVault',
  //     '0xc8fF37F7d057dF1BB9Ad681b53Fa4726f268E0e8',
  //   );
  //
  //   const allCrvPools = {
  //     ...addresses.curve.pools.v3,
  //     ...addresses.curve.pools.crypto,
  //     ...addresses.curve.pools.factory,
  //     ...addresses.curve.pools.cryptofactory,
  //   };
  //   const crvLpTokens = await Promise.all(
  //     Object.values(allCrvPools).map(async (address) => {
  //       return await curveMetaRegistry.getLpToken(address);
  //     }),
  //   );
  //
  //   const poolsLength = (await aladdinConvexVault.poolLength()).toNumber();
  //
  //   const aladdinPools = await Promise.all(
  //     [...Array(poolsLength).keys()].map(async (pid) => {
  //       try {
  //         return await createAladdinPoolInfo(pid, aladdinConvexVault, crvLpTokens, allCrvPools);
  //       } catch (e) {
  //         console.log('could not retrieve pool', pid);
  //         return undefined;
  //       }
  //     }),
  //   );
  //   console.log(aladdinPools.filter((c) => c));
  // }
  //
  // async function createAladdinPoolInfo(pid, acv, crvLpTokens, allCrvPools) {
  //   // console.log('convex booster', convexBooster);
  //   const poolInfo = await acv.poolInfo(pid);
  //   const foundIndex = crvLpTokens
  //     .filter((c) => !!c)
  //     .findIndex((e) => e.toLowerCase() === poolInfo.lpToken.toLowerCase());
  //   if (foundIndex > -1) {
  //     return {
  //       name: Object.keys(allCrvPools)[foundIndex],
  //       lptoken: poolInfo.lpToken,
  //       crvpool: Object.values(allCrvPools)[foundIndex],
  //     };
  //   }
  // }

  describe('Aladdin Pool', function () {
    pick(GARDENS.slice(0, 1)).forEach(async ({ token, name }) => {
      pick(addresses.aladdin.pools).forEach((pool) => {
        it(`can enter into ${pool.name} from a ${name} garden`, async function () {
          await depositIntoAladdin(pool.lptoken, token, pool);
        });
      });
    });

    it(`cannot enter an invalid aladdin pool`, async function () {
      await expect(tryDepositIntoAladdin(ADDRESS_ZERO, addresses.tokens.WETH)).to.be.reverted;
    });
  });

  async function depositIntoAladdin(poolAddress, token, poolObj) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    const gardenReserveAsset = await getERC20(token);
    await depositFunds(token, garden);
    const acrv = await getERC20('0x2b95A1Dcc3D405535f9ed33c219ab38E8d7e0884');

    let integrations = aladdinConcentratorIntegration.address;
    let params = [poolAddress, 0];
    let strategyKind = 'vault';
    let ops = [2];

    // If needs to enter crv first
    if (poolObj.crvpool) {
      strategyKind = 'lpStack';
      integrations = [curvePoolIntegration.address, aladdinConcentratorIntegration.address];
      params = [poolObj.crvpool, 0, poolAddress, 0];
      ops = [1, 2];
    }

    const strategyParams = STRATEGY_PARAMS_MAP[token];
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
    console.log('before execute');
    await executeStrategy(strategyContract, { amount });
    // Check NAV
    const nav = await strategyContract.getNAV();
    expect(nav).to.be.closeTo(amount, amount.div(30));
    if (poolObj.lptoken === '0xD533a949740bb3306d119CC777fa900bA034cd52') {
      expect(await acrv.balanceOf(strategyContract.address)).to.gt(0);
    }
    // Check reward after some time
    await increaseTime(ONE_DAY_IN_SECONDS * 2);

    expect(await strategyContract.getNAV()).to.be.gte(nav.sub(nav.div(100)));

    // If clever signal unlock
    if (poolObj.lptoken === '0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B') {
      await signalUnlockStrategy(strategyContract);
      await increaseTime(ONE_DAY_IN_SECONDS * 17 * 7);
    }

    const balanceBeforeExiting = await gardenReserveAsset.balanceOf(garden.address);
    await finalizeStrategy(strategyContract, { gasLimit: 99900000 });
    console.log('after finalize');

    expect(await strategyContract.getNAV()).to.eq(0);

    if (poolObj.lptoken === '0xD533a949740bb3306d119CC777fa900bA034cd52') {
      expect(await acrv.balanceOf(strategyContract.address)).to.equal(0);
    }

    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.gte(balanceBeforeExiting);
    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.closeTo(
      balanceBeforeExecuting,
      balanceBeforeExecuting.div(30),
    );
  }

  async function tryDepositIntoAladdin(poolAddress, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    await depositFunds(token, garden);
    const strategyContract = await getStrategy({
      kind: 'vault',
      state: 'vote',
      integrations: aladdinConcentratorIntegration.address,
      garden,
      specificParams: [poolAddress, 0],
    });

    await executeStrategy(strategyContract, { amount: STRATEGY_EXECUTE_MAP[token] });
  }
});
