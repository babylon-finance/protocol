const { expect } = require('chai');
const { ethers } = require('hardhat');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  executeStrategy,
  finalizeStrategy,
} = require('../fixtures/StrategyHelper');
const { setupTests } = require('../fixtures/GardenFixture');
const addresses = require('../../lib/addresses');
const { ADDRESS_ZERO } = require('../../lib/constants');

describe.only('HarvestVaultIntegrationTest', function () {
  let harvestVaultIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;

  beforeEach(async () => {
    ({ garden1, harvestVaultIntegration, signer1, signer2, signer3 } = await setupTests()());
  });

  describe('deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await harvestVaultIntegration.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe('Vault', function () {
    let daiToken;
    let daiVault;
    let WETH;

    beforeEach(async () => {
      daiToken = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
      daiVault = await ethers.getContractAt('IHarvestVault', addresses.harvest.vaults.fDAI);
      WETH = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
      console.log('daiVault ', daiVault.address);
    });

    describe('isInvestment', function () {
      it('check that a vault is valid', async function () {
        expect(await harvestVaultIntegration.isInvestment(addresses.harvest.vaults.fDAI)).to.equal(true);
      });

      it('check that a vault is NOT valid', async function () {
        await expect(harvestVaultIntegration.isInvestment(ADDRESS_ZERO)).to.be.revertedWith(/non-contract account/);
      });
    });

    describe('getPricePerShare', function () {
      it('get price per share', async function () {
        expect(await harvestVaultIntegration.getPricePerShare(daiVault.address)).to.equal('1040689410052141025');
      });
    });

    describe('getExpectedShares', function () {
      it('get expected shares', async function () {
        const amountToDeposit = ethers.utils.parseEther('1');
        const shares = await harvestVaultIntegration.getExpectedShares(daiVault.address, amountToDeposit);
        expect(shares).to.equal(0);
      });
    });

    describe('getInvestmentAsset', function () {
      it('get investment assets', async function () {
        const asset = await harvestVaultIntegration.getInvestmentAsset(daiVault.address);
        expect(asset).to.equal(addresses.tokens.DAI);
      });
    });

    describe('execute and finalize', function () {
      it('can enter and exit the dai vault', async function () {
        const strategyContract = await createStrategy(
          'vault',
          'vote',
          [signer1, signer2, signer3],
          harvestVaultIntegration.address,
          garden1,
          DEFAULT_STRATEGY_PARAMS,
          addresses.harvest.vaults.fDAI,
        );

        await executeStrategy(strategyContract);

        expect(await daiVault.balanceOf(strategyContract.address)).to.be.gte(expectedShares);

        await finalizeStrategy(strategyContract, 0);
        expect(await daiVault.balanceOf(strategyContract.address)).to.equal(0);
        expect(await daiToken.balanceOf(strategyContract.address)).to.equal(0);
        expect(await WETH.balanceOf(strategyContract.address)).to.equal(0);
      });
    });
  });
});
