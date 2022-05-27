const { expect } = require('chai');
const { ethers } = require('hardhat');
const { createStrategy, getStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { increaseTime, getERC20, pick } = require('utils/test-helpers');
const { GARDENS, STRATEGY_EXECUTE_MAP, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');

describe('AladdinConcentratorIntegration', function () {
  let aladdinConcentratorIntegration;
  let curvePoolIntegration;
  let curveMetaRegistry;
  let signer1;
  let signer2;
  let signer3;

  beforeEach(async () => {
    ({
      curvePoolIntegration,
      curveMetaRegistry,
      aladdinConcentratorIntegration,
      signer1,
      signer2,
      signer3,
    } = await setupTests()());
    logAladdinPools();
  });

  // Used to create addresses info. do not remove
  async function logAladdinPools() {
    const aladdinConvexVault = await ethers.getContractAt(
      'IAladdinConvexVault',
      '0xc8fF37F7d057dF1BB9Ad681b53Fa4726f268E0e8',
    );

    const allCrvPools = {
      ...addresses.curve.pools.v3,
      ...addresses.curve.pools.crypto,
      ...addresses.curve.pools.factory,
      ...addresses.curve.pools.cryptofactory,
    };
    const crvLpTokens = await Promise.all(
      Object.values(allCrvPools).map(async (address) => {
        return await curveMetaRegistry.getLpToken(address);
      }),
    );

    const poolsLength = (await aladdinConvexVault.poolLength()).toNumber();

    const aladdinPools = await Promise.all(
      [...Array(poolsLength).keys()].map(async (pid) => {
        try {
          return await createAladdinPoolInfo(pid, aladdinConvexVault, crvLpTokens, allCrvPools);
        } catch (e) {
          console.log('could not retrieve pool', pid);
          return undefined;
        }
      }),
    );
    console.log(aladdinPools.filter((c) => c));
  }

  async function createAladdinPoolInfo(pid, acv, crvLpTokens, allCrvPools) {
    // console.log('convex booster', convexBooster);
    const poolInfo = await acv.poolInfo(pid);
    const foundIndex = crvLpTokens
      .filter((c) => !!c)
      .findIndex((e) => e.toLowerCase() === poolInfo.lpToken.toLowerCase());
    if (foundIndex > -1) {
      return {
        name: Object.keys(allCrvPools)[foundIndex],
        lptoken: poolInfo.lpToken,
        crvpool: Object.values(allCrvPools)[foundIndex],
      };
    }
  }

  describe('Aladdin Pool', function () {
    // pick(GARDENS).forEach(async ({ token, name }) => {
    //   pick(addresses.aladin.vaults).forEach((pool) => {
    //     it(`can enter into ${pool.name} from a ${name} garden`, async function () {
    //       await depositIntoAladdin(pool.address, token, pool);
    //     });
    //   });
    // });

    it(`cannot enter an invalid aladdin pool`, async function () {
      await expect(tryDepositIntoAladdin(ADDRESS_ZERO, addresses.tokens.WETH)).to.be.reverted;
    });
  });

  async function depositIntoAladdin(poolAddress, token, poolObj) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    const gardenReserveAsset = await getERC20(token);
    await depositFunds(token, garden);
    const pool = await ethers.getContractAt('IJar', poolAddress);

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
    const strategyContract = await createStrategy(
      strategyKind,
      'vote',
      [signer1, signer2, signer3],
      integrations,
      garden,
      false,
      params,
      ops,
    );

    const amount = STRATEGY_EXECUTE_MAP[token];
    const balanceBeforeExecuting = await gardenReserveAsset.balanceOf(garden.address);
    await executeStrategy(strategyContract, { amount });

    // Check NAV
    const nav = await strategyContract.getNAV();
    expect(nav).to.be.closeTo(amount, amount.div(30));
    expect(await pool.balanceOf(strategyContract.address)).to.gt(0);
    // Check reward after a week
    await increaseTime(ONE_DAY_IN_SECONDS * 7);
    expect(await strategyContract.getNAV()).to.be.gte(nav);

    const balanceBeforeExiting = await gardenReserveAsset.balanceOf(garden.address);
    await finalizeStrategy(strategyContract, { gasLimit: 99900000 });

    expect(await strategyContract.getNAV()).to.eq(0);

    expect(await pool.balanceOf(strategyContract.address)).to.equal(0);

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
