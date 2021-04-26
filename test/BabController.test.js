const { expect } = require('chai');

const addresses = require('../lib/addresses');
const { setupTests } = require('./fixtures/GardenFixture');

describe('BabController', function () {
  let babController;
  let treasury;
  let garden1;
  let garden2;
  let garden3;

  beforeEach(async () => {
    ({ babController, treasury, garden1, garden2, garden3 } = await setupTests()());
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe('Interacting with Communities', function () {
    it('should start with 3 gardens', async function () {
      const gardens = await babController.getGardens();
      expect(gardens.length).to.equal(4);
    });

    it('should set the protocol manager address', async function () {
      expect(await babController.treasury()).to.equal(treasury.address);
    });

    it('can create gardens', async function () {
      expect(!!garden1).to.equal(true);
      expect(!!garden2).to.equal(true);
      expect(!!garden3).to.equal(true);
    });

    it('cannot disable an inactive garden', async function () {
      const initialCommunities = await babController.getGardens();

      await expect(babController.disableGarden(initialCommunities[0])).to.not.be.reverted;
      await expect(babController.disableGarden(initialCommunities[0])).to.be.reverted;
    });

    it('can remove a disabled garden', async function () {
      const initialCommunities = await babController.getGardens();
      expect(initialCommunities.length).to.equal(4);
      await expect(babController.disableGarden(initialCommunities[0])).to.not.be.reverted;
      await babController.removeGarden(initialCommunities[0]);

      const updatedCommunities = await babController.getGardens();
      expect(updatedCommunities.length).to.equal(3);
    });

    it('can enable and disable a garden', async function () {
      const initialCommunities = await babController.getGardens();

      await expect(babController.disableGarden(initialCommunities[0])).to.not.be.reverted;
      await expect(babController.enableGarden(initialCommunities[0])).to.not.be.reverted;
    });
  });

  describe('Keeper List', function () {
    it('can add new keepers', async function () {
      await babController.addKeeper(addresses.users.hardhat3);

      const valid = await babController.isValidKeeper(addresses.users.hardhat3);
      expect(valid).to.equal(true);
    });

    it('can remove keepers', async function () {
      await babController.addKeeper(addresses.users.hardhat3);
      await babController.removeKeeper(addresses.users.hardhat3);

      const valid = await babController.isValidKeeper(addresses.users.hardhat3);
      expect(valid).to.equal(false);
    });

    it('can add keepers in bulk', async function () {
      await babController.addKeepers([addresses.users.hardhat3, addresses.users.hardhat2]);

      expect(await babController.isValidKeeper(addresses.users.hardhat3)).to.equal(true);
      expect(await babController.isValidKeeper(addresses.users.hardhat2)).to.equal(true);
    });
  });

  describe('Protocol operations', function () {
    it('can add a reserve asset', async function () {
      const initialAssets = await babController.getReserveAssets();
      await babController.addReserveAsset(addresses.tokens.DAI);

      const updatedAssets = await babController.getReserveAssets();
      expect(updatedAssets.length > initialAssets.length).to.equal(true);
    });

    it('can remove a reserve asset', async function () {
      await babController.addReserveAsset(addresses.tokens.DAI);
      const initialAssets = await babController.getReserveAssets();

      await babController.removeReserveAsset(initialAssets[0]);

      const updatedAssets = await babController.getReserveAssets();
      expect(updatedAssets.length < initialAssets.length).to.equal(true);
    });

    it('can edit a price oracle', async function () {
      // Note: This is just the wETH address and is testing that the oracle address can be changed
      await expect(babController.editPriceOracle(addresses.tokens.WETH)).to.not.be.reverted;
      const oracle2 = await babController.priceOracle();
      expect(oracle2).to.equal(addresses.tokens.WETH);
    });

    it('can edit a garden valuer', async function () {
      // Note: This is just the wETH address and is testing that the gardenValuer address can be changed
      await expect(babController.editGardenValuer(addresses.tokens.WETH)).to.not.be.reverted;

      const valuer2 = await babController.gardenValuer();
      expect(valuer2).to.equal(addresses.tokens.WETH);
    });

    it('can edit the protocol fee recipient', async function () {
      await babController.editTreasury(addresses.users.hardhat3);

      const recipient = await babController.treasury();
      // TODO(tylerm): Use checksumed addresses
      expect(recipient.toLowerCase()).to.equal(addresses.users.hardhat3);
    });
  });

  // TODO: Integration functions
  // TODO: add functions to update the max fees and test them
});
