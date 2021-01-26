const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

const { loadFixture } = waffle;

const addresses = require("../utils/addresses");
const constants = require("../utils/constants");
const { deployFolioFixture } = require("./fixtures/ControllerFixture");

describe("Position testing", function() {
  let controller;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let userSigner3;
  let fund1;
  let fund2;
  let integrationList;
  let weth;

  beforeEach(async () => {
    const {
      folioController,
      signer1,
      signer2,
      signer3,
      funds,
      integrations,
      owner
    } = await loadFixture(deployFolioFixture);

    integrationList = integrations;
    controller = folioController;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;
    fund1 = funds.one;
    fund2 = funds.two;
    weth = await ethers.getContractAt("IERC20", addresses.tokens.WETH);
  });

  describe("Initial Positions", async function() {
    it("when creating a fund the positions are at 0", async function() {
      expect(await fund2.totalContributors()).to.equal(0);
      expect(await fund2.getPositionCount()).to.equal(0);
      expect(await fund2.totalFunds()).to.equal(ethers.utils.parseEther("0"));
      const wethPosition = await fund1.getPositionBalance(weth.address);
      expect(wethPosition).to.be.gt(ethers.utils.parseEther("0"));
      expect(await fund2.totalSupply()).to.equal(ethers.utils.parseEther("0"));
    });

    it("updates weth position accordingly when initializing the fund", async function() {
      expect(await fund1.totalContributors()).to.equal(1);
      expect(await fund1.getPositionCount()).to.equal(1);
      expect(await fund1.totalFunds()).to.equal(ethers.utils.parseEther("0.1"));
      const wethPosition = await fund1.getPositionBalance(weth.address);
      expect(await weth.balanceOf(fund1.address)).to.equal(
        ethers.utils.parseEther("0.1")
      );
      expect(wethPosition).to.equal(ethers.utils.parseEther("0.1"));
      expect(await fund1.manager()).to.equal(await ownerSigner.getAddress());
      expect(await fund1.balanceOf(ownerSigner.getAddress())).to.equal(
        await fund1.totalSupply()
      );
      expect(await fund1.totalSupply()).to.equal(
        ethers.utils.parseEther("0.1").div(await fund1.initialBuyRate())
      );
    });
  });

  describe("On deposit/ withdrawal", async function() {
    it("supply and positions update accordingly after deposits", async function() {
      const fundBalance = await weth.balanceOf(fund1.address);
      const supplyBefore = await fund1.totalSupply();
      const wethPositionBefore = await fund1.getPositionBalance(weth.address);
      await fund1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      expect(await fund1.totalContributors()).to.equal(2);
      expect(await fund1.getPositionCount()).to.equal(1);
      const wethPosition = await fund1.getPositionBalance(weth.address);
      const fundBalanceAfter = await weth.balanceOf(fund1.address);
      const supplyAfter = await fund1.totalSupply();
      expect(supplyAfter.div(11)).to.equal(supplyBefore);
      expect(fundBalanceAfter.sub(fundBalance)).to.equal(
        ethers.utils.parseEther("1")
      );
      expect(wethPosition.sub(wethPositionBefore)).to.equal(
        ethers.utils.parseEther("1")
      );
      expect(await fund1.totalFunds()).to.equal(ethers.utils.parseEther("1.1"));
      expect(await fund1.totalFundsDeposited()).to.equal(
        ethers.utils.parseEther("1.1")
      );
    });

    it("supply and positions update accordingly after deposits", async function() {
      await fund1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      const fundBalance = await weth.balanceOf(fund1.address);
      const tokenBalance = await fund1.balanceOf(userSigner3.getAddress());
      const supplyBefore = await fund1.totalSupply();
      const wethPositionBefore = await fund1.getPositionBalance(weth.address);
      await controller.changeFundEndDate(fund1.address, constants.NOW); // Ends now
      await fund1
        .connect(userSigner3)
        .withdraw(tokenBalance.div(2), 1, userSigner3.getAddress());
      const wethPosition = await fund1.getPositionBalance(weth.address);
      const fundBalanceAfter = await weth.balanceOf(fund1.address);
      const supplyAfter = await fund1.totalSupply();
      expect(supplyAfter.add(tokenBalance / 2)).to.equal(supplyBefore);
      expect(fundBalance.sub(fundBalanceAfter)).to.equal(
        ethers.utils.parseEther("0.5")
      );
      expect(wethPositionBefore.sub(wethPosition)).to.equal(
        ethers.utils.parseEther("0.5")
      );
      expect(await fund1.totalFunds()).to.equal(ethers.utils.parseEther("0.6"));
      expect(await fund1.totalFundsDeposited()).to.equal(
        ethers.utils.parseEther("1.1")
      );
    });
  });

  describe("Interacting with Borrowing integrations", async function() {
  });

  describe("Interacting with Trade integrations", async function() {
  });

  describe("Interacting with Pool integrations", async function() {
  });

  describe("Interacting with Passive Investment integrations", async function() {
  });

  describe("Fund deposit disabled", async function() {
    it("reverts if the fund is disabled", async function() {
      await fund1.setDisabled();
      await expect(
        fund1
          .connect(userSigner3)
          .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
            value: ethers.utils.parseEther("1")
          })
      ).to.be.reverted;
    });
  });
});
