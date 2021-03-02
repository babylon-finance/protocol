const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

const { loadFixture } = waffle;

const addresses = require("../utils/addresses");
const { deployFolioFixture } = require("./fixtures/ControllerFixture");

describe("PriceOracle", function() {
  let controller;
  let oracle;
  let community;

  beforeEach(async () => {
    const { babController, priceOracle, communitys } = await loadFixture(
      deployFolioFixture
    );
    community = communitys.one;
    controller = babController;
    oracle = priceOracle;
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployedc = await controller.deployed();
      const deployed = await oracle.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedc).to.equal(true);
    });
  });

  describe("UniswapAnchoredView", function() {
    it("should get the price of ETH/DAI", async function() {
      // const price = await community.getPrice(
      //   addresses.tokens.WETH,
      //   addresses.tokens.DAI
      // );
      // expect(price).to.be.gt(ethers.utils.parseEther("500"));
    });

    it("should get the price of DAI/USDC", async function() {
      // const price = await community.getPrice(
      //   addresses.tokens.DAI,
      //   addresses.tokens.USDC
      // );
      // expect(price).to.be.lt(ethers.utils.parseEther("1.1"));
    });
  });

  describe("Uniswap Adapter", function() {
    // TODO
  });
});
