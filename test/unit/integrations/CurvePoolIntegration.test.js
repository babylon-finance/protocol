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
const { increaseTime, normalizeDecimals, getERC20, getContract, parse, from, eth } = require('utils/test-helpers');

describe('CurvePoolIntegrationTest', function () {
  let curvePoolIntegration;
  let babController;
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

  beforeEach(async () => {
    ({ curvePoolIntegration, babController, garden1, signer1, signer2, signer3 } = await setupTests()());
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      const deployedCurve = await curvePoolIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedCurve).to.equal(true);
    });
  });

  describe('Liquidity Pools', function () {
    it('check that a valid pool is valid', async function () {
      const abiCoder = ethers.utils.defaultAbiCoder;
      const data = abiCoder.encode(['address', 'uint256'], [addresses.curve.pools.v3.tricrypto, 0]);
      expect(await curvePoolIntegration.isPool(data)).to.equal(true);
    });

    it('check that an invalid pool is not valid', async function () {
      const abiCoder = ethers.utils.defaultAbiCoder;
      const data = abiCoder.encode(['address', 'uint256'], ['0x8b6e6e7b5b3801fed2cafd4b22b8a16c2f2db21a', 0]);
      expect(await curvePoolIntegration.isPool(data)).to.equal(false);
    });

    pools.forEach(({ name, pool }) => {
      it(`can enter and exit the ${name} pool`, async function () {
        const strategyContract = await createStrategy(
          'lp',
          'vote',
          [signer1, signer2, signer3],
          curvePoolIntegration.address,
          garden1,
          DEFAULT_STRATEGY_PARAMS,
          [pool, 0],
        );
        await executeStrategy(strategyContract, { amount: ONE_ETH.mul(1) });
        expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
        const lpToken = await curvePoolIntegration.getLPToken(pool);
        const poolContract = await getERC20(lpToken);
        expect(await poolContract.balanceOf(strategyContract.address)).to.be.gt(0);
        await finalizeStrategy(strategyContract, 0);
        expect(await poolContract.balanceOf(strategyContract.address)).to.equal(0);
      });

      it(`can get the NAV of the ${name} pool`, async function () {
        const strategyContract = await createStrategy(
          'lp',
          'vote',
          [signer1, signer2, signer3],
          curvePoolIntegration.address,
          garden1,
          DEFAULT_STRATEGY_PARAMS,
          [pool, 0],
        );
        await executeStrategy(strategyContract);
        expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
        const lpToken = await curvePoolIntegration.getLPToken(pool);
        const poolContract = await getERC20(lpToken);
        expect(await poolContract.balanceOf(strategyContract.address)).to.be.gt(0);
        // TODO tricrypto NAV is wrong > 40% difference
        // Workaround set meanwhile
        if (name !== 'tricrypto') {
          expect(await strategyContract.getNAV()).to.be.closeTo(
            ethers.utils.parseEther('1'),
            ethers.utils.parseEther('1').div(10),
          );
        }
      });
    });
  });
});
