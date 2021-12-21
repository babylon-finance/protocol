const { expect } = require('chai');
const { ethers } = require('hardhat');
const { setupTests } = require('fixtures/GardenFixture');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  executeStrategy,
  finalizeStrategy,
} = require('fixtures/StrategyHelper');
const addresses = require('lib/addresses');
const { ONE_ETH } = require('lib/constants');
const { getERC20, eth } = require('utils/test-helpers');

describe('CurvePoolIntegrationTest', function () {
  let curvePoolIntegration;
  let signer1;
  let signer2;
  let signer3;
  let garden1;

  const pools = Object.keys(addresses.curve.pools.v3).map((key) => {
    return {
      name: key,
      pool: addresses.curve.pools.v3[key],
    };
  });

  // Used to create addresses info. do not remove
  async function logCurvePools() {
    const crvAddressProvider = await ethers.getContractAt(
      'ICurveAddressProvider',
      '0x0000000022d53366457f9d5e68ec105046fc4383',
    );
    const crvRegistry = await ethers.getContractAt('ICurveRegistry', await crvAddressProvider.get_registry());
    const curvePoolsD = {};
    const curvePools = await Promise.all(
      [...Array((await crvRegistry.pool_count()).toNumber()).keys()].map(async (pid) => {
        return await getCurvePoolInfo(pid, crvRegistry);
      }),
    );
    curvePools
      .filter((c) => c)
      .forEach((pool) => {
        curvePoolsD[pool.name === '3pool' ? 'tripool' : pool.name] = pool.address;
      });
    console.log('pools', curvePoolsD);
  }

  async function getCurvePoolInfo(pid, crvRegistry) {
    const address = await crvRegistry.pool_list(pid);
    const name = await crvRegistry.get_pool_name(address);
    if (name) {
      return {
        name,
        address,
      };
    }
    return null;
  }

  // logCurvePools();

  beforeEach(async () => {
    ({ curvePoolIntegration, garden1, signer1, signer2, signer3 } = await setupTests()());
  });

  describe('Liquidity Pools', function () {
    it('check that a valid pool is valid', async function () {
      const abiCoder = ethers.utils.defaultAbiCoder;
      const data = abiCoder.encode(['address', 'uint256'], [addresses.curve.pools.v3.tricrypto2, 0]);
      expect(await curvePoolIntegration.isPool(data)).to.equal(true);
    });

    it('check that an invalid pool is not valid', async function () {
      const abiCoder = ethers.utils.defaultAbiCoder;
      const data = abiCoder.encode(['address', 'uint256'], ['0x8b6e6e7b5b3801fed2cafd4b22b8a16c2f2db21a', 0]);
      expect(await curvePoolIntegration.isPool(data)).to.equal(false);
    });

    pools.forEach(({ name, pool }) => {
      it(`can enter and exit the ${name} pool`, async function () {
        const reserveAsset = await getERC20(await garden1.reserveAsset());
        const strategyContract = await createStrategy(
          'lp',
          'vote',
          [signer1, signer2, signer3],
          curvePoolIntegration.address,
          garden1,
          DEFAULT_STRATEGY_PARAMS,
          [pool, 0],
        );

        const gardenBeforeExecuteBalance = await reserveAsset.balanceOf(garden1.address);
        await executeStrategy(strategyContract, { amount: eth() });

        expect(await strategyContract.capitalAllocated()).to.equal(eth());
        const lpToken = await curvePoolIntegration.getLPToken(pool);
        const poolContract = await getERC20(lpToken);
        expect(await poolContract.balanceOf(strategyContract.address)).to.be.gt(0);
        expect(await strategyContract.getNAV()).to.be.closeTo(eth(), eth().div(20));

        const gardenBeforeFinalizeBalance = await reserveAsset.balanceOf(garden1.address);
        await finalizeStrategy(strategyContract, 0);

        expect(await poolContract.balanceOf(strategyContract.address)).to.equal(0);
        expect(await reserveAsset.balanceOf(garden1.address)).to.be.closeTo(gardenBeforeExecuteBalance, gardenBeforeExecuteBalance.div(20));
      });
    });
  });
});
