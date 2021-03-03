const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");
const { loadFixture } = waffle;
const addresses = require("../utils/addresses");
// const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require("../utils/system.js");
const { deployFolioFixture } = require("./fixtures/ControllerFixture");

describe("ReservePool", function() {
  let controller;
  let reserve;
  let community;
  let ownerSigner;
  let userSigner1;
  let userSigner2;

  beforeEach(async () => {
    const {
      babController,
      comunities,
      reservePool,
      signer1,
      signer2,
      owner
    } = await loadFixture(deployFolioFixture);
    ownerSigner = owner;
    community = comunities.one;
    userSigner1 = signer1;
    userSigner2 = signer2;
    controller = babController;
    reserve = reservePool;
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployedc = await controller.deployed();
      const deployed = await reserve.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedc).to.equal(true);
    });
  });

  describe("Constructor", async function() {
    it("the initial controller must be correct", async function() {
      const controllerA = await reserve.controller();
      await expect(controllerA).to.equal(controller.address);
    });
  });

  describe("Deposit", async function() {
    it("cannot deposit below the limit", async function() {
      await expect(
        reserve.connect(userSigner1).deposit({
          value: ethers.utils.parseEther("0.01")
        })
      ).to.be.reverted;
    });
  });
});
