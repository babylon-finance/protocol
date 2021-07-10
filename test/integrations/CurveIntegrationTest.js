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

describe('CurveIntegrationTest', function () {
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
      const deployedBalancer = await curvePoolIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedBalancer).to.equal(true);
    });
  });

  describe('Liquidity Pools', function () {
    let daiWethPool;

    beforeEach(async () => {
      daiWethPool = await ethers.getContractAt('IBPool', addresses.balancer.pools.wethdai);
    });

    it('check that a valid pool is valid', async function () {
      const abiCoder = ethers.utils.defaultAbiCoder;
      const data = abiCoder.encode(['uint256', 'address'], [0, addresses.balancer.pools.wethdai]);
      expect(await curvePoolIntegration.isPool(data)).to.equal(true);
    });

    it('check that an invalid pool is not valid', async function () {
      const abiCoder = ethers.utils.defaultAbiCoder;
      const data = abiCoder.encode(['uint256', 'address'], [0, ADDRESS_ZERO]);
      expect(await curvePoolIntegration.isPool(data)).to.equal(false);
    });

    it('can enter and exit the weth dai pool', async function () {
      const strategyContract = await createStrategy(
        'lp',
        'vote',
        [signer1, signer2, signer3],
        curvePoolIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [0, addresses.balancer.pools.wethdai],
      );
      await executeStrategy(strategyContract);
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
      expect(await daiWethPool.balanceOf(strategyContract.address)).to.be.gt(0);

      await finalizeStrategy(strategyContract, 0);
      expect(await daiWethPool.balanceOf(strategyContract.address)).to.equal(0);
    });
  });
});
