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

  beforeEach(async () => {
    ({ garden1, babController, compoundLendIntegration, signer1, signer2, signer3 } = await loadFixture(
      deployFolioFixture,
    ));
  });

  describe.only('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const babControlerDeployed = await babController.deployed();
      const compoundLendDeployed = await compoundLendIntegration.deployed();
      expect(!!babControlerDeployed).to.equal(true);
      expect(!!compoundLendDeployed).to.equal(true);
    });
  });

  describe('Compound Lend', function () {
    let daiToken;
    let yearnDaiVault;
    let WETH;

    beforeEach(async () => {
      daiToken = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
      WETH = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
    });

    it('can supply and redeem tokens from Compound', async function () {
      const amountToDeposit = ethers.utils.parseEther('1');
      const sharePrice = await yearnDaiVault.getPricePerFullShare();
      const expectedShares = await compoundVaultIntegration.getExpectedShares(yearnDaiVault.address, amountToDeposit);
      const vaultAsset = await compoundVaultIntegration.getInvestmentAsset(yearnDaiVault.address);
      expect(await compoundVaultIntegration.getPricePerShare(yearnDaiVault.address)).to.equal(sharePrice);
      expect(vaultAsset).to.equal(addresses.tokens.DAI);

      const strategyContract = await createStrategy(
        2,
        'vote',
        [signer1, signer2, signer3],
        compoundLendIntegration.address,
        garden1,
      );

      await executeStrategy(garden1, strategyContract, 0);
      expect(await yearnDaiVault.balanceOf(strategyContract.address)).to.be.gte(expectedShares);

      await finalizeStrategy(garden1, strategyContract, 0);
      expect(await yearnDaiVault.balanceOf(strategyContract.address)).to.equal(0);
      expect(await daiToken.balanceOf(strategyContract.address)).to.equal(0);
      expect(await WETH.balanceOf(strategyContract.address)).to.equal(ethers.BigNumber.from('995973117600718893'));
    });
  });
});
