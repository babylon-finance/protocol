const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

const { loadFixture } = waffle;

const addresses = require("../utils/addresses");
const { ONE_DAY_IN_SECONDS } = require("../utils/constants.js");
const { deployFolioFixture } = require("./fixtures/ControllerFixture");

describe("Community Ideas", function() {
  let controller;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let userSigner3;
  let community1;
  let ideas;
  let weth;

  beforeEach(async () => {
    const {
      babController,
      signer1,
      signer2,
      signer3,
      comunities,
      owner
    } = await loadFixture(deployFolioFixture);

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
});
