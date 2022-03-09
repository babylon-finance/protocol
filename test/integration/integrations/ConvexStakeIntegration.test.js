const { expect } = require('chai');
const { ethers } = require('hardhat');
const { createStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { increaseTime, getERC20, pick } = require('utils/test-helpers');
const { STRATEGY_EXECUTE_MAP, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');

describe('ConvexStakeIntegrationTest', function () {
  let convexStakeIntegration;
  let curvePoolIntegration;
  let curveMetaRegistry;
  let signer1;
  let signer2;
  let signer3;

  // Used to create addresses info. do not remove
  async function logConvexPools() {
    const convexpools = await Promise.all(
      [...Array(70).keys()].map(async (pid) => {
        return await createConvexPoolInfo(pid);
      }),
    );
    console.log(convexpools.filter((c) => c));
  }

  async function createConvexPoolInfo(pid) {
    const convexBooster = await ethers.getContractAt('IBooster', '0xF403C135812408BFbE8713b5A23a04b3D48AAE31');
    const poolInfo = await convexBooster.poolInfo(pid);
    const allCrvPools = {
      ...addresses.curve.pools.v3,
      ...addresses.curve.pools.crypto,
      ...addresses.curve.pools.factory,
    };
    const crvLpTokens = await Promise.all(
      Object.values(allCrvPools).map(async (address) => {
        return await curveMetaRegistry.getLpToken(address);
      }),
    );
    const foundIndex = crvLpTokens.findIndex((e) => e === poolInfo[0]);
    if (foundIndex > -1) {
      return {
        name: Object.keys(allCrvPools)[foundIndex],
        crvpool: Object.values(allCrvPools)[foundIndex],
        cvxpool: poolInfo[1],
      };
    }
  }

  beforeEach(async () => {
    ({
      curvePoolIntegration,
      curveMetaRegistry,
      convexStakeIntegration,
      signer1,
      signer2,
      signer3,
    } = await setupTests()());
    // logConvexPools();
  });

  describe('Convex Stake Multigarden multiasset', function () {
    pick([
      { token: addresses.tokens.WETH, name: 'WETH' },
      { token: addresses.tokens.DAI, name: 'DAI' },
      { token: addresses.tokens.USDC, name: 'USDC' },
      { token: addresses.tokens.WBTC, name: 'WBTC' },
    ]).forEach(async ({ token, name }) => {
      pick(addresses.convex.pools).forEach(({ crvpool, cvxpool, name }) => {
        it(`can enter ${name} CRV pool and stake into convex`, async function () {
          await depositAndStakeStrategy(crvpool, cvxpool, token);
        });
      });
    });
    it(`cannot enter an invalid pool`, async function () {
      await expect(tryDepositAndStakeStrategy(ADDRESS_ZERO, ADDRESS_ZERO, addresses.tokens.WETH)).to.be.reverted;
    });
  });

  async function depositAndStakeStrategy(crvpool, cvxpool, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    const gardenReserveAsset = await getERC20(token);
    await depositFunds(token, garden);
    const convexBooster = await ethers.getContractAt('IBooster', '0xF403C135812408BFbE8713b5A23a04b3D48AAE31');
    const crvLpToken = await getERC20(await curveMetaRegistry.getLpToken(crvpool));
    const pid = (await convexStakeIntegration.getPid(cvxpool))[1].toNumber();
    const poolInfo = await convexBooster.poolInfo(pid);
    const convexRewardToken = await getERC20(poolInfo[3]);

    const strategyContract = await createStrategy(
      'lpStack',
      'vote',
      [signer1, signer2, signer3],
      [curvePoolIntegration.address, convexStakeIntegration.address],
      garden,
      false,
      [crvpool, 0, cvxpool, 0],
    );
    const amount = STRATEGY_EXECUTE_MAP[token];
    const balanceBeforeExecuting = await gardenReserveAsset.balanceOf(garden.address);
    await executeStrategy(strategyContract, { amount });
    // Check NAV
    const nav = await strategyContract.getNAV();
    expect(nav).to.be.gt(amount.sub(amount.div(35)));

    expect(await crvLpToken.balanceOf(strategyContract.address)).to.equal(0);
    expect(await convexRewardToken.balanceOf(strategyContract.address)).to.be.gt(0);

    // Check reward after a week
    await increaseTime(ONE_DAY_IN_SECONDS * 7);
    expect(await strategyContract.getNAV()).to.be.closeTo(nav, nav.div(100));
    const balanceBeforeExiting = await gardenReserveAsset.balanceOf(garden.address);
    await finalizeStrategy(strategyContract, { gasLimit: 99900000 });
    expect(await crvLpToken.balanceOf(strategyContract.address)).to.equal(0);
    expect(await convexRewardToken.balanceOf(strategyContract.address)).to.equal(0);

    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.gte(balanceBeforeExiting);
    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.closeTo(
      balanceBeforeExecuting,
      balanceBeforeExecuting.div(35),
    );
  }

  async function tryDepositAndStakeStrategy(crvpool, cvxpool, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    await depositFunds(token, garden);

    const strategyContract = await createStrategy(
      'lpStack',
      'vote',
      [signer1, signer2, signer3],
      [curvePoolIntegration.address, convexStakeIntegration.address],
      garden,
      false,
      [crvpool, 0, cvxpool, 0],
    );
    await expect(executeStrategy(strategyContract, { amount: STRATEGY_EXECUTE_MAP[token] })).to.be.reverted;
  }
});
