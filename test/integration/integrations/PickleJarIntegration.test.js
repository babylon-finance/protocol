const { expect } = require('chai');
const { ethers } = require('hardhat');
const { createStrategy, getStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { increaseTime, getERC20, pick, eth } = require('utils/test-helpers');
const { STRATEGY_EXECUTE_MAP, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');

describe('PickleJarIntegrationTest', function () {
  let pickleJarIntegration;
  let curvePoolIntegration;
  let sushiswapPoolIntegration;
  let uniswapPoolIntegration;
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
  //
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

  // logConvexPools();

  beforeEach(async () => {
    ({
      pickleJarIntegration,
      curvePoolIntegration,
      sushiswapPoolIntegration,
      uniswapPoolIntegration,
      signer1,
      signer2,
      signer3,
    } = await setupTests()());
  });

  describe('Pickle Jar Multigarden multiasset', function () {
    [
      { token: addresses.tokens.WETH, name: 'WETH' },
      // { token: addresses.tokens.DAI, name: 'DAI' },
      // { token: addresses.tokens.USDC, name: 'USDC' },
      // { token: addresses.tokens.WBTC, name: 'WBTC' },
    ].forEach(async ({ token, name }) => {
      pick(addresses.pickle.jars).forEach((jar) => {
        it.only(`can enter into ${jar.name} jar from a ${name} garden`, async function () {
          await depositIntoJar(jar.address, token, jar);
        });
      });
    });
    it(`cannot enter an invalid pool`, async function () {
      await expect(tryDepositIntoJar(ADDRESS_ZERO, addresses.tokens.WETH)).to.be.reverted;
    });
  });

  async function depositIntoJar(jarAddress, token, jarObj) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    const gardenReserveAsset = await getERC20(token);
    await depositFunds(token, garden);
    const jar = await ethers.getContractAt('IJar', jarAddress);

    let integrations = pickleJarIntegration.address;
    let params = [jarAddress, 0];
    let strategyKind = 'vault';

    // If needs to enter crv first
    if (jarObj.crvpool) {
      strategyKind = 'lpStack';
      integrations = [curvePoolIntegration.address, pickleJarIntegration.address];
      params = [jarObj.crvpool, 0, jarAddress, 0];
    }
    // If needs to enter sushi first
    if (jarObj.sushi) {
      strategyKind = 'lpStack';
      integrations = [sushiswapPoolIntegration.address, pickleJarIntegration.address];
      params = [jarObj.sushi, 0, jarAddress, 0];
    }
    // If needs to enter univ2 first
    if (jarObj.uni) {
      strategyKind = 'lpStack';
      integrations = [uniswapPoolIntegration.address, pickleJarIntegration.address];
      params = [jarObj.uni, 0, jarAddress, 0];
    }

    const strategyContract = await createStrategy(
      strategyKind,
      'vote',
      [signer1, signer2, signer3],
      integrations,
      garden,
      false,
      params,
      { maxTradeSlippagePercentage: eth(0.1) },
    );

    const amount = STRATEGY_EXECUTE_MAP[token];
    const balanceBeforeExecuting = await gardenReserveAsset.balanceOf(garden.address);
    console.log('before execute');
    await executeStrategy(strategyContract, { amount });
    // Check NAV
    console.log('after execute');
    const nav = await strategyContract.getNAV();
    expect(nav).to.be.gt(amount.sub(amount.div(35)));
    expect(await jar.balanceOf(strategyContract.address)).to.gt(0);
    // Check reward after a week
    await increaseTime(ONE_DAY_IN_SECONDS * 7);
    expect(await strategyContract.getNAV()).to.be.gte(nav);
    const balanceBeforeExiting = await gardenReserveAsset.balanceOf(garden.address);
    console.log('before finalize');
    await finalizeStrategy(strategyContract, { gasLimit: 99900000 });
    expect(await jar.balanceOf(strategyContract.address)).to.equal(0);

    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.gte(balanceBeforeExiting);
    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.closeTo(
      balanceBeforeExecuting,
      balanceBeforeExecuting.div(35),
    );
  }

  async function tryDepositIntoJar(jarAddress, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    await depositFunds(token, garden);
    const strategyContract = await getStrategy({
      kind: 'vault',
      state: 'vote',
      integrations: pickleJarIntegration.address,
      garden,
      specificParams: [jarAddress, 0],
    });

    await executeStrategy(strategyContract, { amount: STRATEGY_EXECUTE_MAP[token] });
  }
});
