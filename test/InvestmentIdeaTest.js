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
  let ideasC;
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
      ideas,
      owner
    } = await loadFixture(deployFolioFixture);

    balancerIntegration = integrations.balancerIntegration;
    controller = babController;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;
    community1 = comunities.one;
    ideasC = ideas;
    weth = await ethers.getContractAt("IERC20", addresses.tokens.WETH);
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await ideasC[0].deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe("Ideator can change the duration", function() {
    it("ideator should be able to change the duration of an investment idea", async function() {
      await expect(
        ideasC[0]
          .connect(userSigner1)
          .changeInvestmentDuration(ONE_DAY_IN_SECONDS)
      ).to.not.be.reverted;
    });

    it("other member should be able to change the duration of an investment idea", async function() {
      await expect(
        ideasC[0]
          .connect(userSigner3)
          .changeInvestmentDuration(ONE_DAY_IN_SECONDS)
      ).to.be.reverted;
    });
  });
});
