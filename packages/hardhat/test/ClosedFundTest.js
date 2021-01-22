const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

const { loadFixture } = waffle;

const addresses = require("../utils/addresses");
const constants = require("../utils/constants");
const { deployFolioFixture } = require("./fixtures/ControllerFixture");

describe("Fund", function() {
  let controller;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let userSigner3;
  let fund1;
  let fund2;
  let fund3;
  let weth;

  beforeEach(async () => {
    const {
      folioController,
      signer1,
      signer2,
      signer3,
      funds,
      owner
    } = await loadFixture(deployFolioFixture);

    controller = folioController;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;
    fund1 = funds.one;
    fund2 = funds.two;
    fund3 = funds.three;
    weth = await ethers.getContractAt("IERC20", addresses.tokens.WETH);
  });

  describe("Fund construction", async function() {
    it("should have expected properties upon deployment", async function() {
      expect(await fund1.totalContributors()).to.equal(1);
      expect(await fund1.manager()).to.equal(await ownerSigner.getAddress());
    });
  });

  describe("Fund state", async function() {
    it("only the current manager or protocol should be able to update active state", async function() {
      await expect(fund1.connect(userSigner1).setActive(true)).to.be.reverted;
    });

    it("only the current manager or the protocol should be able to update the manager", async function() {
      await expect(
        fund1.connect(userSigner3).setManager(userSigner3.getAddress())
      ).to.be.reverted;
    });

    it("the stake and initial deposit must be correct", async function() {
      const balance = await fund1.signer.getBalance();
      await expect(balance).to.be.gt(ethers.utils.parseEther("0.099"));
      await expect(await fund1.managerStake()).to.equal(
        ethers.utils.parseEther("0.1")
      );
    });
  });

  describe("Fund deposit limit", async function() {
    it("reverts if the deposit is bigger than the limit", async function() {
      await fund1.setDepositLimit(ethers.utils.parseEther("1"));
      await expect(
        fund1
          .connect(userSigner3)
          .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
            value: ethers.utils.parseEther("1")
          })
      ).to.be.reverted;
    });
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

  describe("Fund contributors", async function() {
    it("a contributor can make an initial deposit", async function() {
      expect(await fund1.totalContributors()).to.equal(1);
      const fundBalance = await weth.balanceOf(fund1.address);
      const supplyBefore = await fund1.totalSupply();
      await fund1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      const fundBalanceAfter = await weth.balanceOf(fund1.address);
      const supplyAfter = await fund1.totalSupply();
      // Funds
      // Manager deposit in fixture is only 0.1
      expect(supplyAfter.div(11)).to.equal(supplyBefore);
      expect(fundBalanceAfter.sub(fundBalance)).to.equal(
        ethers.utils.parseEther("1")
      );
      expect(await fund1.totalContributors()).to.equal(2);
      expect(await fund1.totalFunds()).to.equal(ethers.utils.parseEther("1.1"));
      expect(await fund1.totalFundsDeposited()).to.equal(
        ethers.utils.parseEther("1.1")
      );
      // Positions
      expect(await fund1.getPositionCount()).to.equal(1);
      const wethPosition = await fund1.getTrackedBalance(weth.address);
      expect(wethPosition).to.be.gt(ethers.utils.parseEther("1.0099"));
      // Contributor Struct
      const contributor = await fund1.contributors(userSigner3.getAddress());
      expect(contributor.totalDeposit).to.equal(ethers.utils.parseEther("1"));
      expect(contributor.tokensReceived).to.equal(
        supplyAfter.sub(supplyBefore)
      );
    });

    it("a contributor can make multiple deposits", async function() {
      await fund1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      await fund1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      // Note: Fund is initialized with manager as first contributor, hence the count and totalFunds delta
      expect(await fund1.totalContributors()).to.equal(2);
      expect(await fund1.totalFunds()).to.equal(
        ethers.utils.parseEther("2.1")
      );
    });

    it("multiple contributors can make deposits", async function() {
      await fund1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });

      await fund1
        .connect(userSigner2)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner2.getAddress(), {
          value: ethers.utils.parseEther("1")
        });

      // Note: Fund is initialized with manager as first contributor
      expect(await fund1.totalContributors()).to.equal(3);
      expect(await fund1.totalFunds()).to.equal(ethers.utils.parseEther("2.1"));
    });

    it("a contributor can withdraw funds if they have enough in deposits", async function() {
      await fund1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      await controller.changeFundEndDate(fund1.address, constants.NOW); // Ends now
      expect(await fund1.totalFunds()).to.equal(ethers.utils.parseEther("1.1"));
      expect(await fund1.totalContributors()).to.equal(2);
      await fund1
        .connect(userSigner3)
        .withdraw(1000000, 1, userSigner3.getAddress());
    });

    it("a contributor cannot withdraw funds until the time ends", async function() {
      await fund1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      expect(await fund1.totalFunds()).to.equal(ethers.utils.parseEther("1.1"));
      expect(await fund1.totalContributors()).to.equal(2);
      await expect(
        fund1
          .connect(userSigner3)
          .withdraw(1000000, 1, userSigner3.getAddress())
      ).to.be.reverted;
    });

    it("a contributor cannot make a deposit when the fund ends", async function() {
      await controller.changeFundEndDate(fund1.address, constants.NOW); // Ends now
      await expect(
        fund1
          .connect(userSigner3)
          .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
            value: ethers.utils.parseEther("1")
          })
      ).to.be.reverted;
    });

    it("a contributor cannot withdraw more funds than they have deposited", async function() {
      await fund1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      await controller.changeFundEndDate(fund1.address, constants.NOW); // Ends now
      expect(await fund1.totalFunds()).to.equal(ethers.utils.parseEther("1.1"));
      expect(await fund1.totalContributors()).to.equal(2);
      await expect(
        fund1
          .connect(userSigner3)
          .withdraw(10000000, 2, userSigner3.getAddress())
      ).to.be.reverted;
      await expect(
        fund1
          .connect(userSigner3)
          .withdraw(1000001, 2, userSigner3.getAddress())
      ).to.be.reverted;
    });
  });
});
