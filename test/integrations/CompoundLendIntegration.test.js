const { expect } = require('chai');
const { waffle, ethers } = require('hardhat');
const { createStrategy, executeStrategy, finalizeStrategy } = require('../fixtures/StrategyHelper');
const { deployFolioFixture } = require('../fixtures/ControllerFixture');
const addresses = require('../../utils/addresses');
const { ADDRESS_ZERO } = require('../../utils/constants');

const { loadFixture } = waffle;

describe('CompoundLendIntegrationTest', function () {
  let compoundLendIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let babController;
  let USDC;
  let CUSDC;
  let WETH;

  beforeEach(async () => {
    ({ garden1, babController, compoundLendIntegration, signer1, signer2, signer3 } = await loadFixture(
      deployFolioFixture,
    ));
    USDC = await ethers.getContractAt('IERC20', addresses.tokens.USDC);
    CUSDC = await ethers.getContractAt('IERC20', addresses.tokens.CUSDC);
    WETH = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const babControlerDeployed = await babController.deployed();
      const compoundLendDeployed = await compoundLendIntegration.deployed();
      expect(!!babControlerDeployed).to.equal(true);
      expect(!!compoundLendDeployed).to.equal(true);
    });
  });

  describe('Compound Lend', function () {
    it('can supply to valid cToken', async function () {
      expect(await compoundLendIntegration.isInvestment(addresses.tokens.USDC)).to.equal(true);
    });

    it('fails to suplly to invlaid address', async function () {
      expect(await compoundLendIntegration.isInvestment(ADDRESS_ZERO)).to.equal(false);
    });

    it('can supply and redeem tokens from Compound', async function () {
      const strategyContract = await createStrategy(
        'lend',
        'vote',
        [signer1, signer2, signer3],
        compoundLendIntegration.address,
        garden1,
      );

      await executeStrategy(strategyContract);
      expect(await USDC.balanceOf(strategyContract.address)).to.be.equal(0);
      expect(await CUSDC.balanceOf(strategyContract.address)).to.be.gte(0);

      await finalizeStrategy(strategyContract);
      expect(await USDC.balanceOf(strategyContract.address)).to.equal(0);
      expect(await CUSDC.balanceOf(strategyContract.address)).to.be.equal(0);
      expect(await WETH.balanceOf(strategyContract.address)).to.equal(0);
    });

    // TODO: test supply/borrow for WETH
  });
});
