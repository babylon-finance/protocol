const { expect } = require('chai');
const { waffle, ethers } = require('hardhat');
const { deployFolioFixture } = require('../fixtures/ControllerFixture');
const { createStrategy, executeStrategy, finalizeStrategy } = require('../fixtures/StrategyHelper');
const addresses = require('../../utils/addresses');
const { ADDRESS_ZERO } = require('../../utils/constants');

const { loadFixture } = waffle;

describe('BalancerIntegrationTest', function () {
  let balancerIntegration;
  let babController;
  let signer1;
  let signer2;
  let signer3;
  let garden1;

  beforeEach(async () => {
    ({ balancerIntegration, babController, garden1, signer1, signer2, signer3 } = await loadFixture(
      deployFolioFixture,
    ));
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      const deployedBalancer = await balancerIntegration.deployed();
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
      expect(await balancerIntegration.isPool(addresses.balancer.pools.wethdai)).to.equal(true);
    });

    it('check that an invalid pool is not valid', async function () {
      expect(await balancerIntegration.isPool(ADDRESS_ZERO)).to.equal(false);
    });

    it.only('can enter and exit the weth dai pool', async function () {
      const strategyContract = await createStrategy(
        1,
        'vote',
        [signer1, signer2, signer3],
        balancerIntegration.address,
        garden1,
      );

      await executeStrategy(garden1, strategyContract);
      expect(await daiWethPool.balanceOf(strategyContract.address)).to.be.gt(0);

      await finalizeStrategy(garden1, strategyContract, 0);
      expect(await daiWethPool.balanceOf(strategyContract.address)).to.equal(0);
    });
  });
});
