const { expect } = require("chai");
const { ethers } = require("hardhat");
const { waffle } = require("hardhat");

const { loadFixture } = waffle;

const addresses = require("../utils/addresses");
const { deployFolioFixture } = require("./fixtures/ControllerFixture");

async function createFunds(controller, managerSigner, recipientSigner) {
  // Note: for now the integrations here are not real addresses for our integration contract,
  // we should be sure to deploy those and include soon. See deploy.js for an example.
  const fund1 = await controller.createFund(
    [addresses.tokens.WETH],
    addresses.tokens.WETH,
    addresses.tokens.sUSD,
    managerSigner.getAddress(),
    recipientSigner.getAddress(),
    "Fund Number One",
    "FNON",
    ethers.utils.parseEther("1")
  );

  const fund2 = await controller.createFund(
    [addresses.tokens.WETH],
    addresses.tokens.WETH,
    addresses.tokens.sUSD,
    managerSigner.getAddress(),
    recipientSigner.getAddress(),
    "Fund Number TWO",
    "FNTW",
    ethers.utils.parseEther("1")
  );

  const fund3 = await controller.createFund(
    [addresses.tokens.WETH],
    addresses.tokens.WETH,
    addresses.tokens.sUSD,
    managerSigner.getAddress(),
    recipientSigner.getAddress(),
    "Fund Number Three",
    "FNTH",
    ethers.utils.parseEther("10")
  );

  return { fund1, fund2, fund3 };
}

describe("FolioController", function() {
  let controller;
  let oracle;
  let valuer;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let userSigner3;

  beforeEach(async () => {
    const {
      folioController,
      priceOracle,
      fundValuer,
      owner,
      signer1,
      signer2,
      signer3
    } = await loadFixture(deployFolioFixture);

    controller = folioController;
    oracle = priceOracle;
    valuer = fundValuer;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;
    console.log(
      "Config:",
      oracle,
      valuer,
      ownerSigner,
      userSigner1,
      userSigner2,
      userSigner3
    );
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await controller.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe("Interacting with Funds", function() {
    it("should start empty", async function() {
      expect(await controller.getFunds()).to.eql([]);
    });
    it("should set the protocol manager address", async function() {
      expect(await controller.getFeeRecipient()).to.equal(
        addresses.users.hardhat1
      );
    });

    it("can create a funds", async function() {
      const { fund1, fund2, fund3 } = await createFunds(
        controller,
        userSigner1,
        userSigner1
      );
      expect(!!fund1).to.equal(true);
      expect(!!fund2).to.equal(true);
      expect(!!fund3).to.equal(true);
    });

    it("can create funds and retrieve all addresses", async function() {
      await createFunds(controller, userSigner1, userSigner1);
      const funds = await controller.getFunds();
      expect(funds.length).to.equal(3);
    });

    it("can remove a fund", async function() {
      await createFunds(controller, userSigner1, userSigner1);

      const initialFunds = await controller.getFunds();
      expect(initialFunds.length).to.equal(3);

      await controller.removeFund(initialFunds[0]);

      const updatedFunds = await controller.getFunds();
      expect(updatedFunds.length).to.equal(2);
    });

    it("cannot disable an inactive fund", async function() {
      await createFunds(controller, userSigner1, userSigner1);
      const initialFunds = await controller.getFunds();

      await expect(controller.disableFund(initialFunds[0])).to.be.reverted;
    });

    it("can enable and disable a fund", async function() {
      await createFunds(controller, userSigner1, userSigner1);
      const initialFunds = await controller.getFunds();

      await expect(controller.enableFund(initialFunds[0])).to.not.be.reverted;
      await expect(controller.disableFund(initialFunds[0])).to.not.be.reverted;
    });
  });
});
