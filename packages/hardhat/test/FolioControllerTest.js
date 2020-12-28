const { expect } = require("chai");
const { ethers } = require("hardhat");
const { waffle } = require("hardhat");
const { loadFixture } = waffle;

const { fixture } = require("./fixtures/FolioController");

const ADD_FUND_PROPS = ["new fund", "NewFundToken", "NFT"];
const ADD_FUND_PROPS_2 = ["new fund 2", "NewFundToken2", "NFT2"];

describe("FolioController", function() {
  beforeEach(async () => {
    await loadFixture(fixture);
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await folioController.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  //   describe("Interacting with Funds", function() {
  //     it("should start empty", async function() {
  //       expect(await folioController.totalFunds()).to.equal(0);
  //       expect(await folioController.currentFundIndex()).to.equal(1);
  //     });

  //     it("should set the protocol manager address", async function() {
  //       expect(await folioController.protocolManager()).to.equal(
  //         await owner.getAddress()
  //       );
  //     });

  //     it("can add a hedge fund and retrieve it", async function() {
  //       expect(await folioController.addFund(...ADD_FUND_PROPS));
  //       expect(await folioController.totalFunds()).to.equal(1);
  //       expect(await folioController.currentFundIndex()).to.equal(2);
  //       const { name, active, index } = await folioController.getFund(
  //         ADD_FUND_PROPS[0]
  //       );
  //       expect(name).to.equal(ADD_FUND_PROPS[0]);
  //       expect(active).to.equal(false);
  //       expect(index).to.equal(1);
  //     });

  //     it("can add a hedge funds and retrieve all", async function() {
  //       expect(await folioController.addFund(...ADD_FUND_PROPS));
  //       expect(await folioController.addFund(...ADD_FUND_PROPS_2));
  //       expect(await folioController.totalFunds()).to.equal(2);
  //       expect(await folioController.currentFundIndex()).to.equal(3);
  //       const funds = await folioController.getAllFunds();
  //       expect(funds.length).to.equal(2);
  //     });

  //     it("only protocol manager can add hedge funds", async function() {
  //       await expect(folioController.connect(addr2).addFund(...ADD_FUND_PROPS)).to
  //         .be.reverted;
  //     });

  //     it("can not add the same hedge fund twice", async function() {
  //       expect(await folioController.addFund(...ADD_FUND_PROPS));
  //       await expect(folioController.addFund(...ADD_FUND_PROPS)).to.be.reverted;
  //     });

  //     it("can disable a hedge fund and retrieve it", async function() {
  //       expect(await folioController.addFund(...ADD_FUND_PROPS));
  //       expect(await folioController.totalFunds()).to.equal(1);
  //       expect(await folioController.currentFundIndex()).to.equal(2);
  //       expect(await folioController.disableFund(ADD_FUND_PROPS[0]));
  //       const { name, active, index } = await folioController.getFund(
  //         ADD_FUND_PROPS[0]
  //       );
  //       expect(name).to.equal(ADD_FUND_PROPS[0]);
  //       expect(active).to.equal(false);
  //       expect(index).to.equal(1);
  //       expect(await folioController.totalFunds()).to.equal(0);
  //     });

  //     it("can not disable a hedge fund that does not exist", async function() {
  //       await expect(folioController.disableFund("my imaginary fund")).to.be
  //         .reverted;
  //     });

  //     it("can reenable a hedge fund after disabling it", async function() {
  //       expect(await folioController.addFund(...ADD_FUND_PROPS));
  //       expect(await folioController.totalFunds()).to.equal(1);
  //       expect(await folioController.currentFundIndex()).to.equal(2);
  //       expect(await folioController.disableFund(ADD_FUND_PROPS[0]));
  //       expect(await folioController.totalFunds()).to.equal(0);
  //       expect(await folioController.reenableFund(ADD_FUND_PROPS[0]));
  //       const { name, active, index } = await folioController.getFund(
  //         ADD_FUND_PROPS[0]
  //       );
  //       expect(name).to.equal(ADD_FUND_PROPS[0]);
  //       expect(active).to.equal(true);
  //       expect(index).to.equal(1);
  //       expect(await folioController.totalFunds()).to.equal(1);
  //     });
  //   });
});
