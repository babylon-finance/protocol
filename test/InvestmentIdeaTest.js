const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

const { loadFixture } = waffle;

const addresses = require("../utils/addresses");
const { ONE_DAY_IN_SECONDS, EMPTY_BYTES } = require("../utils/constants.js");
const { deployFolioFixture } = require("./fixtures/ControllerFixture");

describe("Investment Idea", function() {
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

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await ideas.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe("Ideator can change the duration", function() {
    it("ideator should be able to change the duration of an investment idea", async function() {
      await community1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      await expect(
        community1
          .connect(userSigner3)
          .addInvestmentIdea(
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
      ).to.not.be.reverted;
      await expect(
        ideas
          .connect(userSigner3)
          .changeInvestmentDuration(0, ONE_DAY_IN_SECONDS)
      ).to.not.be.reverted;
    });
  });
});
