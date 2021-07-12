const { expect } = require('chai');
const { ethers } = require('hardhat');
const { setupTests } = require('../fixtures/GardenFixture');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  executeStrategy,
  finalizeStrategy,
} = require('../fixtures/StrategyHelper');
const addresses = require('../../lib/addresses');
const { ADDRESS_ZERO, ONE_ETH } = require('../../lib/constants');

describe('CurvePoolIntegrationTest', function () {
  let curvePoolIntegration;
  let babController;
  let signer1;
  let signer2;
  let signer3;
  let garden1;

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
    let triCryptoPool;

    beforeEach(async () => {
      triCryptoPool = await ethers.getContractAt('ICurvePoolV3', addresses.curve.pools.v3.tricrypto);
    });

    it('check that a valid pool is valid', async function () {
      const abiCoder = ethers.utils.defaultAbiCoder;
      const data = abiCoder.encode(['address', 'uint256'], [addresses.curve.pools.v3.tricrypto, 0]);
      expect(await curvePoolIntegration.isPool(data)).to.equal(true);
    });

    it('check that an invalid pool is not valid', async function () {
      const abiCoder = ethers.utils.defaultAbiCoder;
      const data = abiCoder.encode(['address', 'uint256'], ['0x8b6e6e7b5b3801fed2cafd4b22b8a16c2f2db21a', 0]);
      await expect(curvePoolIntegration.isPool(data)).to.be.reverted;
    });

    it('can enter and exit the weth dai pool', async function () {
      const strategyContract = await createStrategy(
        'lp',
        'vote',
        [signer1, signer2, signer3],
        curvePoolIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [addresses.curve.pools.v3.tripool, 0],
      );
      console.log('before execute');
      await executeStrategy(strategyContract);
      console.log('after execute');
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
      expect(await triCryptoPool.balanceOf(strategyContract.address)).to.be.gt(0);

      await finalizeStrategy(strategyContract, 0);
      expect(await triCryptoPool.balanceOf(strategyContract.address)).to.equal(0);
    });
  });
});
