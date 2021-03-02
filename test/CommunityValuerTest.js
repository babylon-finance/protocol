const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

const { loadFixture } = waffle;

const addresses = require("../utils/addresses");
const { deployFolioFixture } = require("./fixtures/ControllerFixture");

describe("CommunityValuer", function() {
  let controller;
  let valuer;
  let community;
  let weth;

  beforeEach(async () => {
    const { babController, communityValuer, comunities } = await loadFixture(
      deployFolioFixture
    );
    community = comunities.one;
    controller = babController;
    valuer = communityValuer;
    weth = await ethers.getContractAt("IERC20", addresses.tokens.WETH);
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployedc = await controller.deployed();
      const deployed = await valuer.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedc).to.equal(true);
    });
  });

  describe("Calls CommunityValuer", function() {
    it("should return 0.1 for community1", async function() {
      const wethInCommunity = await weth.balanceOf(community.address);
      // const priceOfWeth = await community.getPrice(
      //   addresses.tokens.WETH,
      //   addresses.tokens.DAI
      // );
      console.log("wethInCommunity", wethInCommunity);
      // console.log('format', ethers.utils.formatEther(100000000000000000));
      const pricePerCommunityToken = await valuer.calculateCommunityValuation(
        community.address,
        addresses.tokens.WETH
      );
      const tokens = await community.totalSupply();
      expect(pricePerCommunityToken.mul(tokens / 1000).div(10 ** 15)).to.equal(
        ethers.utils.parseEther("0.1")
      );
    });
  });
});
