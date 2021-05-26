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
const { ADDRESS_ZERO, ONE_ETH } = require('../../lib/constants');

describe('HarvestVaultIntegrationTest', function () {
  let harvestVaultIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let daiVault;

  beforeEach(async () => {
    ({ garden1, harvestVaultIntegration, signer1, signer2, signer3 } = await setupTests()());
    daiVault = await ethers.getContractAt('IHarvestVault', addresses.harvest.vaults.fDAI);
  });

  describe('deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await harvestVaultIntegration.deployed();
      expect(!!deployed).to.equal(true);
    });
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
      expect(await harvestVaultIntegration.getExpectedShares(daiVault.address, ONE_ETH)).to.equal('960901485439250901');
    });
  });

  describe('getInvestmentAsset', function () {
    it('get investment asset', async function () {
      expect(await harvestVaultIntegration.getInvestmentAsset(daiVault.address)).to.equal(addresses.tokens.DAI);
    });
  });

  describe('execute and finalize', function () {
    it('can enter and exit the DAI vault', async function () {
      const strategyContract = await createStrategy(
        'vault',
        'vote',
        [signer1, signer2, signer3],
        harvestVaultIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        addresses.harvest.vaults.fDAI,
      );

      expect(await daiVault.balanceOf(strategyContract.address)).to.equal(0);

      await executeStrategy(strategyContract);

      expect(await daiVault.balanceOf(strategyContract.address)).to.be.closeTo('3790822207262591447883', 0); // roughly ONE ETH in fDAI

      await finalizeStrategy(strategyContract, 0);

      expect(await daiVault.balanceOf(strategyContract.address)).to.equal(0);
    });
  });
});
