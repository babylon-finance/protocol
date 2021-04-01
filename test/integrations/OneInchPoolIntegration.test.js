const { expect } = require('chai');
const { waffle, ethers } = require('hardhat');
const { deployFolioFixture } = require('../fixtures/ControllerFixture');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  executeStrategy,
  finalizeStrategy,
} = require('../fixtures/StrategyHelper');
const addresses = require('../../utils/addresses');
const { ADDRESS_ZERO } = require('../../utils/constants');

const { loadFixture } = waffle;

describe('OneInchPoolIntegrationTest', function () {
  let oneInchPoolIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let babController;

  beforeEach(async () => {
    ({ babController, garden1, oneInchPoolIntegration, signer1, signer2, signer3 } = await loadFixture(
      deployFolioFixture,
    ));
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      const deployedUni = await oneInchPoolIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedUni).to.equal(true);
    });
  });

  describe('Liquidity Pools', function () {
    let daiWethPair;

    beforeEach(async () => {
      daiWethPair = await ethers.getContractAt('IMooniswap', addresses.oneinch.pools.wethdai);
    });

    it('check that a valid pool is valid', async function () {
      expect(await oneInchPoolIntegration.isPool(addresses.oneinch.pools.wethdai)).to.equal(true);
    });

    it('check that an invalid pool is not valid', async function () {
      expect(await oneInchPoolIntegration.isPool(ADDRESS_ZERO)).to.equal(false);
    });

    it('can enter and exit the weth wbtc pool', async function () {
      // const strategyContract = await createStrategy(
      //   1,
      //   'vote',
      //   [signer1, signer2, signer3],
      //   oneInchPoolIntegration.address,
      //   garden1,
      //   DEFAULT_STRATEGY_PARAMS,
      //   [daiWethPair.address],
      // );
      // await executeStrategy(garden1, strategyContract, 0);
      // expect(await daiWethPair.balanceOf(strategyContract.address)).to.be.gt(0);
      //
      // await finalizeStrategy(garden1, strategyContract, 0);
      // expect(await daiWethPair.balanceOf(strategyContract.address)).to.equal(0);
    });

    it('can enter and exit the eth dai pool', async function () {
      const strategyContract = await createStrategy(
        1,
        'vote',
        [signer1, signer2, signer3],
        oneInchPoolIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [daiWethPair.address],
      );
      await executeStrategy(garden1, strategyContract, 0);
      expect(await daiWethPair.balanceOf(strategyContract.address)).to.be.gt(0);

      await finalizeStrategy(garden1, strategyContract, 0);
      expect(await daiWethPair.balanceOf(strategyContract.address)).to.equal(0);
    });
  });
});
