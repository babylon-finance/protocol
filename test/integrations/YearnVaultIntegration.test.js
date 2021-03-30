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

    beforeEach(async () => {
      daiToken = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
      yearnDaiVault = await ethers.getContractAt('IVault', addresses.yearn.vaults.ydai);
    });

    it('check that a valid yearn vault is valid', async function () {
      expect(await yearnVaultIntegration.isInvestment(addresses.yearn.vaults.ydai)).to.equal(true);
    });

    it('check that an invalid vault is not valid', async function () {
      await expect(yearnVaultIntegration.isInvestment(ADDRESS_ZERO)).to.be.reverted;
    });

    it('can enter and exit the yearn dai vault', async function () {
      // Keep this comment to have an example of impersonation
      // whaleSigner = await impersonateAddress(addresses.holders.DAI);
      // expect(
      //   await daiToken
      //     .connect(whaleSigner)
      //     .transfer(garden.address, ethers.utils.parseEther("1000"), {
      //       gasPrice: 0
      //     })
      // );
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      const amountToDeposit = ethers.utils.parseEther('1000');
      const sharePrice = await yearnDaiVault.getPricePerFullShare();
      const expectedYShares = amountToDeposit.div(sharePrice);

      const expectedShares2 = await yearnVaultIntegration.getExpectedShares(yearnDaiVault.address, amountToDeposit);
      expect(expectedShares2).to.equal(expectedYShares);
      expect(await yearnVaultIntegration.getPricePerShare(yearnDaiVault.address)).to.equal(sharePrice);

      const strategyContract = await createStrategy(
        2,
        'vote',
        [signer1, signer2, signer3],
        yearnVaultIntegration.address,
        garden1,
      );

      await executeStrategy(garden1, strategyContract, 0);
      console.log('price', ethers.utils.formatEther(sharePrice));
      console.log('yshares to receive', expectedYShares.toString());
      expect(await yearnDaiVault.balanceOf(garden1.address)).to.be.gte(expectedYShares);

      await finalizeStrategy(garden1, strategyContract, 0);
      expect(await yearnDaiVault.balanceOf(garden1.address)).to.equal(0);
      expect(await daiToken.balanceOf(garden1.address)).to.equal(0);
    });
  });
});
