const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

const { loadFixture } = waffle;

const addresses = require("../utils/addresses");
const { deployFolioFixture } = require("./fixtures/ControllerFixture");

describe("BabController", function() {
  let controller;
  let oracle;
  let valuer;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let userSigner3;
  let fund1;
  let fund2;
  let fund3;

  beforeEach(async () => {
    const {
      babController,
      priceOracle,
      fundValuer,
      owner,
      signer1,
      funds,
      signer2,
      signer3
    } = await loadFixture(deployFolioFixture);

    controller = babController;
    oracle = priceOracle;
    valuer = fundValuer;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;
    fund1 = funds.one;
    fund2 = funds.two;
    fund3 = funds.three;
    // console.log(
    //   "Config:",
    //   oracle,
    //   valuer,
    //   ownerSigner,
    //   userSigner1,
    //   userSigner2,
    //   userSigner3
    // );
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await controller.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe("Interacting with Funds", function() {
    it("should start with 3 funds", async function() {
      const funds = await controller.getFunds();
      expect(funds.length).to.equal(3);
    });

    it("should set the protocol manager address", async function() {
      expect(await controller.getFeeRecipient()).to.equal(
        addresses.users.hardhat1
      );
    });

    it("can create funds", async function() {
      expect(!!fund1).to.equal(true);
      expect(!!fund2).to.equal(true);
      expect(!!fund3).to.equal(true);
    });

    it("can create funds and retrieve all addresses", async function() {
      const funds = await controller.getFunds();
      expect(funds.length).to.equal(3);
    });

    it("can remove a fund", async function() {
      const initialFunds = await controller.getFunds();
      expect(initialFunds.length).to.equal(3);

      await controller.removeFund(initialFunds[0]);

      const updatedFunds = await controller.getFunds();
      expect(updatedFunds.length).to.equal(2);
    });

    it("cannot disable an inactive fund", async function() {
      const initialFunds = await controller.getFunds();

      await expect(controller.disableFund(initialFunds[0])).to.not.be.reverted;
      await expect(controller.disableFund(initialFunds[0])).to.be.reverted;
    });

    it("can enable and disable a fund", async function() {
      const initialFunds = await controller.getFunds();

      await expect(controller.disableFund(initialFunds[0])).to.not.be.reverted;
      await expect(controller.enableFund(initialFunds[0])).to.not.be.reverted;
    });
  });

  describe("Whitelisted assets", function() {
    const YFI = "0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e";
    const ZRX = "0xe41d2489571d322189246dafa5ebde1f4699f498";
    it("can add new whitelisted assets", async function() {
      await controller.addAssetWhitelist(YFI);

      const valid = await controller.isValidAsset(YFI);
      expect(valid).to.equal(true);
    });

    it("can remove whitelisted assets", async function() {
      await controller.addAssetWhitelist(YFI);
      await controller.removeAssetWhitelist(YFI);

      const valid = await controller.isValidAsset(YFI);
      expect(valid).to.equal(false);
    });

    it("can add whitelisted assets in bulk", async function() {
      await controller.addAssetsWhitelist([YFI, ZRX]);

      expect(await controller.isValidAsset(YFI)).to.equal(true);
      expect(await controller.isValidAsset(ZRX)).to.equal(true);
    });
  });

  describe("Keeper List", function() {
    it("can add new keepers", async function() {
      await controller.addKeeper(addresses.users.hardhat3);

      const valid = await controller.isValidKeeper(addresses.users.hardhat3);
      expect(valid).to.equal(true);
    });

    it("can remove whitelisted assets", async function() {
      await controller.addKeeper(addresses.users.hardhat3);
      await controller.removeKeeper(addresses.users.hardhat3);

      const valid = await controller.isValidKeeper(addresses.users.hardhat3);
      expect(valid).to.equal(false);
    });

    it("can add whitelisted assets in bulk", async function() {
      await controller.addKeepers([
        addresses.users.hardhat3,
        addresses.users.hardhat2
      ]);

      expect(await controller.isValidKeeper(addresses.users.hardhat3)).to.equal(
        true
      );
      expect(await controller.isValidKeeper(addresses.users.hardhat2)).to.equal(
        true
      );
    });
  });

  describe("Protocol operations", function() {
    it("can add a reserve asset", async function() {
      const initialAssets = await controller.getReserveAssets();
      await controller.addReserveAsset(addresses.tokens.DAI);

      const updatedAssets = await controller.getReserveAssets();
      expect(updatedAssets.length > initialAssets.length).to.equal(true);
    });

    it("can remove a reserve asset", async function() {
      await controller.addReserveAsset(addresses.tokens.DAI);
      const initialAssets = await controller.getReserveAssets();

      await controller.removeReserveAsset(initialAssets[0]);

      const updatedAssets = await controller.getReserveAssets();
      expect(updatedAssets.length < initialAssets.length).to.equal(true);
    });

    it("can edit a price oracle", async function() {
      // Note: This is just the wETH address and is testing that the oracle address can be changed
      await expect(controller.editPriceOracle(addresses.tokens.WETH)).to.not.be
        .reverted;
      const oracle2 = await controller.getPriceOracle();
      expect(oracle2).to.equal(addresses.tokens.WETH);
    });

    it("can edit a fund valuer", async function() {
      // Note: This is just the wETH address and is testing that the fundValuer address can be changed
      await expect(controller.editFundValuer(addresses.tokens.WETH)).to.not.be
        .reverted;

      const valuer2 = await controller.getFundValuer();
      expect(valuer2).to.equal(addresses.tokens.WETH);
    });

    it("can edit the protocol fee recipient", async function() {
      await controller.editFeeRecipient(addresses.users.hardhat3);

      const recipient = await controller.getFeeRecipient();
      // TODO(tylerm): Look into why this toLowerCase is needed here.
      expect(recipient.toLowerCase()).to.equal(addresses.users.hardhat3);
    });
  });

  // TODO: Integration functions
  // TODO: add functions to update the max fees and test them
});
