const { expect } = require('chai');

const addresses = require('lib/addresses');
const { GARDEN_PARAMS_STABLE, GARDEN_PARAMS, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { impersonateAddress } = require('lib/rpc');
const { createStrategy, executeStrategy, finalizeStrategy, getStrategy } = require('fixtures/StrategyHelper');
const { createGarden } = require('fixtures/GardenHelper');
const { increaseTime, normalizeDecimals, getERC20, getContract, parse, from, eth } = require('utils/test-helpers');
const { ethers } = require('hardhat');

describe('BabController', function () {
  let controller;
  let signer1;
  let signer2;
  let owner;
  let erc20;

  beforeEach(async () => {
    [, , owner, signer1, signer2] = await ethers.getSigners();
    const controllerFactory = await ethers.getContractFactory('BabController');
    controller = await controllerFactory.deploy();
    await controller.connect(owner).initialize();

    const erc20Fatory = await ethers.getContractFactory('ERC20Mock');
    erc20 = await erc20Fatory.deploy('Babylon Finance', 'BABL', owner.address, eth(1e6));
  });

  describe('keepers', function () {
    it('can add new keepers', async function () {
      await controller.connect(owner).addKeeper(addresses.users.hardhat3);

      const valid = await controller.isValidKeeper(addresses.users.hardhat3);
      expect(valid).to.equal(true);
    });

    it('can remove keepers', async function () {
      await controller.connect(owner).addKeeper(addresses.users.hardhat3);
      await controller.connect(owner).removeKeeper(addresses.users.hardhat3);

      const valid = await controller.isValidKeeper(addresses.users.hardhat3);
      expect(valid).to.equal(false);
    });

    it('can add keepers in bulk', async function () {
      await controller.connect(owner).addKeepers([addresses.users.hardhat3, addresses.users.hardhat2]);

      expect(await controller.isValidKeeper(addresses.users.hardhat3)).to.equal(true);
      expect(await controller.isValidKeeper(addresses.users.hardhat2)).to.equal(true);
    });
  });

  describe('addReserveAsset', function () {
    it('can add a reserve asset', async function () {
      await controller.connect(owner).addReserveAsset(erc20.address);

      expect(await controller.validReserveAsset(erc20.address)).to.eq(true);
    });

    it('can remove a reserve asset', async function () {
      await controller.connect(owner).addReserveAsset(erc20.address);
      expect(await controller.validReserveAsset(erc20.address)).to.eq(true);

      await controller.connect(owner).removeReserveAsset(erc20.address);
      expect(await controller.validReserveAsset(erc20.address)).to.eq(false);
    });
  });

  describe('editPriceOracle', function () {
    it('can edit a price oracle', async function () {
      await controller.connect(owner).editPriceOracle(addresses.tokens.WETH);
      expect(await controller.connect(owner).priceOracle()).to.equal(addresses.tokens.WETH);
    });
  });

  describe('editGardenValuer', function () {
    it('can edit a garden valuer', async function () {
      await controller.connect(owner).editGardenValuer(addresses.tokens.WETH);

      expect(await controller.gardenValuer()).to.equal(addresses.tokens.WETH);
    });
  });

  describe('editTreasury', function () {
    it('can edit the protocol fee recipient', async function () {
      await controller.connect(owner).editTreasury(addresses.tokens.WETH);

      expect(await controller.treasury()).to.equal(addresses.tokens.WETH);
    });
  });

  describe('enableGardenTokensTransfers', function () {
    it('can enable token transfers after 2021', async function () {
      await controller.connect(owner).enableGardenTokensTransfers();
      expect(await controller.gardenTokensTransfersEnabled()).to.equal(true);
    });
  });

  describe('setPauseGuardian', function () {
    it('can set a pause guardian from owner', async function () {
      await controller.connect(owner).setPauseGuardian(signer1.address);
      expect(await controller.guardian()).to.equal(signer1.address);
    });

    it('can set a new pause guardian from current pause guardian', async function () {
      await controller.connect(owner).setPauseGuardian(signer1.address);
      await controller.connect(signer1).setPauseGuardian(signer2.address);

      expect(await controller.guardian()).to.equal(signer2.address);
    });

    it('can NOT set zero address as pause guardian from current pause guardian', async function () {
      await controller.connect(owner).setPauseGuardian(signer1.address);
      await expect(controller.connect(signer1).setPauseGuardian(ADDRESS_ZERO)).to.be.revertedWith(
        'Guardian cannot remove himself',
      );
      expect(await controller.guardian()).to.equal(signer1.address);
    });

    it('can set zero address as pause guardian from the owner', async function () {
      await controller.connect(owner).setPauseGuardian(signer1.address);
      const guardian = await controller.guardian();

      expect(guardian).to.equal(signer1.address);

      await controller.connect(owner).setPauseGuardian(ADDRESS_ZERO);
      expect(await controller.guardian()).to.equal(ADDRESS_ZERO);
    });

    it('should fail if trying to set a pause a user without enough rights', async function () {
      await expect(controller.connect(signer2).setPauseGuardian(signer2.address)).to.be.revertedWith(
        'only pause guardian and owner can update pause guardian',
      );
    });
  });
});
