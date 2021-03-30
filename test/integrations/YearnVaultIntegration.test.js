const { expect } = require('chai');
const { waffle, ethers } = require('hardhat');
const { createStrategy, executeStrategy, finalizeStrategy } = require('../fixtures/StrategyHelper');
const { deployFolioFixture } = require('../fixtures/ControllerFixture');
const addresses = require('../../utils/addresses');
const { ADDRESS_ZERO } = require('../../utils/constants');

const { loadFixture } = waffle;

describe('YearnVaultIntegrationTest', function () {
  let yearnVaultIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let babController;

  beforeEach(async () => {
    ({ garden1, babController, yearnVaultIntegration, signer1, signer2, signer3 } = await loadFixture(
      deployFolioFixture,
    ));
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      const deployedYearn = await yearnVaultIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedYearn).to.equal(true);
    });
  });

  describe('Yearn Vaults', function () {
    let daiToken;
    let yearnDaiVault;
    let WETH;

    beforeEach(async () => {
      daiToken = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
      yearnDaiVault = await ethers.getContractAt('IVault', addresses.yearn.vaults.ydai);
      WETH = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
    });

    it('check that a valid yearn vault is valid', async function () {
      expect(await yearnVaultIntegration.isInvestment(addresses.yearn.vaults.ydai)).to.equal(true);
    });

    it('check that an invalid vault is not valid', async function () {
      await expect(yearnVaultIntegration.isInvestment(ADDRESS_ZERO)).to.be.reverted;
    });

    it('can enter and exit the yearn dai vault', async function () {
      const amountToDeposit = ethers.utils.parseEther('1');
      const sharePrice = await yearnDaiVault.getPricePerFullShare();
      const expectedShares = await yearnVaultIntegration.getExpectedShares(yearnDaiVault.address, amountToDeposit);
      const vaultAsset = await yearnVaultIntegration.getInvestmentAsset(yearnDaiVault.address);
      expect(await yearnVaultIntegration.getPricePerShare(yearnDaiVault.address)).to.equal(sharePrice);
      expect(vaultAsset).to.equal(addresses.tokens.DAI);

      const strategyContract = await createStrategy(
        2,
        'vote',
        [signer1, signer2, signer3],
        yearnVaultIntegration.address,
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
