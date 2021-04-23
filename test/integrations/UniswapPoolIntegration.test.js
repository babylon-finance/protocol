const { expect } = require('chai');
const { waffle, ethers } = require('hardhat');
const { deployFolioFixture } = require('../fixtures/ControllerFixture');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  executeStrategy,
  finalizeStrategy,
} = require('../fixtures/StrategyHelper');
const addresses = require('../../lib/addresses');
const { ADDRESS_ZERO } = require('../../lib/constants');

const { loadFixture } = waffle;

describe('UniswapPoolIntegrationTest', function () {
  let uniswapPoolIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let babController;

  beforeEach(async () => {
    ({ babController, garden1, uniswapPoolIntegration, signer1, signer2, signer3 } = await loadFixture(
      deployFolioFixture,
    ));
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      const deployedUni = await uniswapPoolIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedUni).to.equal(true);
    });
  });

  describe('Liquidity Pools', function () {
    let daiWethPair;

    beforeEach(async () => {
      daiWethPair = await ethers.getContractAt('IUniswapV2PairB', addresses.uniswap.pairs.wethdai);
    });

    it('check that a valid pool is valid', async function () {
      expect(await uniswapPoolIntegration.isPool(addresses.uniswap.pairs.wethdai)).to.equal(true);
    });

    it('check that an invalid pool is not valid', async function () {
      await expect(uniswapPoolIntegration.isPool(ADDRESS_ZERO)).to.be.reverted;
    });

    it('can enter and exit the weth dai pool', async function () {
      const strategyContract = await createStrategy(
        'pool',
        'vote',
        [signer1, signer2, signer3],
        uniswapPoolIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [daiWethPair.address],
      );
      await executeStrategy(strategyContract);
      expect(await daiWethPair.balanceOf(strategyContract.address)).to.be.gt(0);

      await finalizeStrategy(strategyContract, 0);
      expect(await daiWethPair.balanceOf(strategyContract.address)).to.equal(0);
    });
  });
});
