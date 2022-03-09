const { expect } = require('chai');
const { ethers } = require('hardhat');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden } = require('fixtures/GardenHelper');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  executeStrategy,
  finalizeStrategy,
} = require('fixtures/StrategyHelper');
const addresses = require('lib/addresses');
const { getERC20, eth, pick } = require('utils/test-helpers');

describe('CurvePoolIntegrationTest', function () {
  let curvePoolIntegration;
  let paladinStakeIntegration;
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
  const cryptopools = Object.keys(addresses.curve.pools.crypto).map((key) => {
    return {
      name: key,
      pool: addresses.curve.pools.crypto[key],
    };
  });

  const factorypools = Object.keys(addresses.curve.pools.factory).map((key) => {
    return {
      name: key,
      pool: addresses.curve.pools.factory[key],
    };
  });

  const cryptofactorypools = Object.keys(addresses.curve.pools.cryptofactory).map((key) => {
    return {
      name: key,
      pool: addresses.curve.pools.cryptofactory[key],
    };
  });

  // Used to create addresses info. do not remove
  async function logCurvePools() {
    const crvAddressProvider = await ethers.getContractAt(
      'ICurveAddressProvider',
      '0x0000000022d53366457f9d5e68ec105046fc4383',
    );
    const crvRegistry = await ethers.getContractAt('ICurveRegistry', await crvAddressProvider.get_address(0));
    const factoryRegistry = await ethers.getContractAt('ICurveRegistry', await crvAddressProvider.get_address(3));
    const cryptoRegistry = await ethers.getContractAt('ICurveRegistry', await crvAddressProvider.get_address(5));
    const cryptoFactoryRegistry = await ethers.getContractAt('ICurveRegistry', await crvAddressProvider.get_address(6));
    const curvePoolsD = {};
    let curvePools = await Promise.all(
      [...Array((await crvRegistry.pool_count()).toNumber()).keys()].map(async (pid) => {
        return await getCurvePoolInfo(pid, crvRegistry);
      }),
    );
    curvePools = curvePools.concat(
      await Promise.all(
        [...Array((await factoryRegistry.pool_count()).toNumber()).keys()].map(async (pid) => {
          return await getCurvePoolInfo(pid, factoryRegistry, true);
        }),
      ),
    );
    curvePools = curvePools.concat(
      await Promise.all(
        [...Array((await cryptoRegistry.pool_count()).toNumber()).keys()].map(async (pid) => {
          return await getCurvePoolInfo(pid, cryptoRegistry, false, true);
        }),
      ),
    );
    curvePools = curvePools.concat(
      await Promise.all(
        [...Array((await cryptoFactoryRegistry.pool_count()).toNumber()).keys()].map(async (pid) => {
          return await getCurvePoolInfo(pid, cryptoFactoryRegistry, true, true);
        }),
      ),
    );
    curvePools
      .filter((c) => c)
      .forEach((pool) => {
        curvePoolsD[pool.name === '3pool' ? 'tripool' : pool.name] = pool.address;
      });
    console.log('pools', curvePoolsD);
  }

  async function getCurvePoolInfo(pid, crvRegistry, isFactory = false, isCrypto = false) {
    // TODO: Need to filter by TVL
    const address = await crvRegistry.pool_list(pid);
    const name = isFactory ? `factory${isCrypto ? 'c' : ''}` + pid : await crvRegistry.get_pool_name(address);
    if (name) {
      return {
        name,
        address,
        isFactory,
        isCrypto,
      };
    }
    return null;
  }

  // logCurvePools();

  async function testCurvePool(name, pool) {
    const slippage = ['compound', 'susd', 'y', 'aeth'].includes(name) ? eth().div(3) : eth().div(20);
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
    expect(await strategyContract.getNAV()).to.be.closeTo(eth(), slippage);
    await finalizeStrategy(strategyContract, 0);
    expect(await poolContract.balanceOf(strategyContract.address)).to.equal(0);
    expect(await reserveAsset.balanceOf(garden1.address)).to.be.closeTo(gardenBeforeExecuteBalance, slippage);
  }

  beforeEach(async () => {
    ({ curvePoolIntegration, garden1, signer1, signer2, signer3 } = await setupTests()());
  });

  describe('Liquidity Pools', function () {
    it('check that a valid pool is valid', async function () {
      const abiCoder = ethers.utils.defaultAbiCoder;
      const data = abiCoder.encode(['address', 'uint256'], [addresses.curve.pools.v3.tripool, 0]);
      expect(await curvePoolIntegration.isPool(data)).to.equal(true);
    });

    it('check that an invalid pool is not valid', async function () {
      const abiCoder = ethers.utils.defaultAbiCoder;
      const data = abiCoder.encode(['address', 'uint256'], ['0x8b6e6e7b5b3801fed2cafd4b22b8a16c2f2db21a', 0]);
      expect(await curvePoolIntegration.isPool(data)).to.equal(false);
    });

    pick(pools).forEach(({ name, pool }) => {
      it(`can enter and exit the ${name} pool`, async function () {
        await testCurvePool(name, pool);
      });
    });

    pick(cryptopools).forEach(({ name, pool }) => {
      it(`can enter and exit the crypto ${name} pool`, async function () {
        await testCurvePool(name, pool);
      });
    });

    pick(factorypools).forEach(({ name, pool }) => {
      it(`can enter and exit the factory ${name} pool`, async function () {
        await testCurvePool(name, pool);
      });
    });

    pick(cryptofactorypools).forEach(({ name, pool }) => {
      it(`can enter and exit the factory ${name} pool`, async function () {
        if (pool !== addresses.curve.pools.cryptofactory.palstkaave) {
          await testCurvePool(name, pool);
        }
      });
    });
  });
});
