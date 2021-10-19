const { expect } = require('chai');
const { ethers } = require('hardhat');
const { createStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { increaseTime, normalizeDecimals, getERC20, getContract, parse, from, eth } = require('utils/test-helpers');
const { STRATEGY_EXECUTE_MAP, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');

describe('ConvexStakeIntegrationTest', function () {
  let convexStakeIntegration;
  let curvePoolIntegration;
  let signer1;
  let signer2;
  let signer3;

  // Used to create addresses info. do not remove
  // async function logConvexPools() {
  //   const convexpools = await Promise.all(
  //     [...Array(40).keys()].map(async (pid) => {
  //       return await createConvexPoolInfo(pid);
  //     }),
  //   );
  //   console.log(convexpools.filter((c) => c));
  // }
  // logConvexPools();
  // const pools = [
  // {
  //   crvpool: '0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7',
  //   cvxpool: '0x30d9410ed1d5da1f6c8391af5338c93ab8d4035c',
  //   name: 'tripool',
  // },
  // {
  //   crvpool: '0xA2B47E3D5c44877cca798226B7B8118F9BFb7A56',
  //   cvxpool: '0x32512Bee3848bfcBb7bEAf647aa697a100f3b706',
  //   name: 'compound',
  // },
  //   {
  //     crvpool: '0x52EA46506B9CC5Ef470C5bf89f17Dc28bB35D85C',
  //     cvxpool: '0xA1c3492b71938E144ad8bE4c2fB6810b01A43dD8',
  //     name: 'usdt',
  //   },
  // ];

  // async function createConvexPoolInfo(pid) {
  //   const crvAddressProvider = await ethers.getContractAt(
  //     'ICurveAddressProvider',
  //     '0x0000000022d53366457f9d5e68ec105046fc4383',
  //   );
  //   const convexBooster = await ethers.getContractAt('IBooster', '0xF403C135812408BFbE8713b5A23a04b3D48AAE31');
  //   const crvRegistry = await ethers.getContractAt('ICurveRegistry', await crvAddressProvider.get_registry());
  //   const poolInfo = await convexBooster.poolInfo(pid);
  //   const crvLpTokens = await Promise.all(
  //     Object.values(addresses.curve.pools.v3).map(async (address) => {
  //       return await crvRegistry.get_lp_token(address);
  //     }),
  //   );
  //   const foundIndex = crvLpTokens.findIndex((e) => e === poolInfo[0]);
  //   if (foundIndex > -1) {
  //     return {
  //       name: Object.keys(addresses.curve.pools.v3)[foundIndex],
  //       crvpool: Object.values(addresses.curve.pools.v3)[foundIndex],
  //       cvxpool: poolInfo[1],
  //     };
  //   }
  // }

  beforeEach(async () => {
    ({ curvePoolIntegration, convexStakeIntegration, signer1, signer2, signer3 } = await setupTests()());
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const lendDeployed = await convexStakeIntegration.deployed();
      expect(!!lendDeployed).to.equal(true);
    });
  });

  describe('Convex Stake Multigarden multiasset', function () {
    [
      { token: addresses.tokens.WETH, name: 'WETH' },
      // { token: addresses.tokens.DAI, name: 'DAI' },
      // { token: addresses.tokens.USDC, name: 'USDC' },
      // { token: addresses.tokens.WBTC, name: 'WBTC' },
    ].forEach(async ({ token, name }) => {
      addresses.convex.pools.forEach(({ crvpool, cvxpool, name }) => {
        it(`can enter ${name} CRV pool and stake into convex`, async function () {
          // TODO: fix usdt pool
          if (name === 'usdt') return;
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
    const crvAddressProvider = await ethers.getContractAt(
      'ICurveAddressProvider',
      '0x0000000022d53366457f9d5e68ec105046fc4383',
    );
    const crvRegistry = await ethers.getContractAt('ICurveRegistry', await crvAddressProvider.get_registry());
    const convexBooster = await ethers.getContractAt('IBooster', '0xF403C135812408BFbE8713b5A23a04b3D48AAE31');
    const crvLpToken = await getERC20(await crvRegistry.get_lp_token(crvpool));
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
    await executeStrategy(strategyContract, { amount });
    // Check NAV
    const nav = await strategyContract.getNAV();
    expect(nav).to.be.gt(amount.sub(amount.div(50)));

    expect(await crvLpToken.balanceOf(strategyContract.address)).to.equal(0);
    expect(await convexRewardToken.balanceOf(strategyContract.address)).to.be.gt(0);

    // Check reward after a week
    await increaseTime(ONE_DAY_IN_SECONDS * 7);
    expect(await strategyContract.getNAV()).to.be.gte(nav);
    const balanceBeforeExiting = await gardenReserveAsset.balanceOf(garden.address);
    await finalizeStrategy(strategyContract);
    expect(await crvLpToken.balanceOf(strategyContract.address)).to.equal(0);
    expect(await convexRewardToken.balanceOf(strategyContract.address)).to.equal(0);

    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.gt(balanceBeforeExiting);
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
