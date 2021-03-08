const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

const { loadFixture } = waffle;

const addresses = require("../utils/addresses");
const { ONE_DAY_IN_SECONDS, EMPTY_BYTES } = require("../utils/constants.js");
const { deployFolioFixture } = require("./fixtures/ControllerFixture");

describe("Community Ideas", function() {
  let controller;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let userSigner3;
  let community1;
  let ideas;
  let balancerIntegration;
  let weth;

  beforeEach(async () => {
    const {
      babController,
      signer1,
      signer2,
      signer3,
      comunities,
      integrations,
      owner
    } = await loadFixture(deployFolioFixture);

    balancerIntegration = integrations.balancerIntegration;
    controller = babController;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;
    community1 = comunities.one;
    weth = await ethers.getContractAt("IERC20", addresses.tokens.WETH);
    ideas = await ethers.getContractAt(
      "CommunityIdeas",
      await community1.communityIdeas()
    );
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await ideas.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe("Community construction", async function() {
    it("should have expected properties upon deployment", async function() {
      expect(await ideas.controller()).to.equal(controller.address);
      expect(await ideas.community()).to.equal(community1.address);
      expect(await ideas.ideaCooldownPeriod()).to.equal(ONE_DAY_IN_SECONDS);
      expect(await ideas.ideaCreatorProfitPercentage()).to.equal(
        ethers.utils.parseEther("0.13")
      );
      expect(await ideas.ideaVotersProfitPercentage()).to.equal(
        ethers.utils.parseEther("0.05")
      );
      expect(await ideas.communityCreatorProfitPercentage()).to.equal(
        ethers.utils.parseEther("0.02")
      );
      expect(await ideas.minVotersQuorum()).to.equal(
        ethers.utils.parseEther("0.10")
      );
      expect(await ideas.minIdeaDuration()).to.equal(ONE_DAY_IN_SECONDS * 3);
      expect(await ideas.maxIdeaDuration()).to.equal(ONE_DAY_IN_SECONDS * 365);
    });
  });

  describe("Add Investment Idea", async function() {
    it("should not be able to add an investment idea unless there is a contributor", async function() {
      await expect(
        ideas.addInvestmentIdea(
          ethers.utils.parseEther("10"),
          ethers.utils.parseEther("1"),
          ONE_DAY_IN_SECONDS * 15,
          EMPTY_BYTES,
          EMPTY_BYTES,
          balancerIntegration.address,
          ethers.utils.parseEther("0.05"),
          ethers.utils.parseEther("2"),
          [addresses.tokens.DAI],
          [ethers.utils.parseEther("100")],
          {
            gasLimit: 9500000,
            gasPrice: 0
          }
        )
      ).to.be.reverted;
    });

    it("should be able to add an investment idea", async function() {
      await community1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
    });
  });
});
