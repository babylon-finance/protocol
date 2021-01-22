const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

const { loadFixture } = waffle;

const addresses = require("../utils/addresses");
const { deployFolioFixture } = require("./fixtures/ControllerFixture");

describe("FundValuer", function() {
  let controller;
  let valuer;
  let fund;
  let weth;

  beforeEach(async () => {
    const { folioController, fundValuer, funds } = await loadFixture(
      deployFolioFixture
    );
    fund = funds.one;
    controller = folioController;
    valuer = fundValuer;
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

  describe("Calls FundValuer", function() {
    it("should return 0.01 for fund1", async function() {
      const wethInFund = await weth.balanceOf(fund.address);
      const priceOfWeth = await fund.getPrice(
        addresses.tokens.WETH,
        addresses.tokens.DAI
      );
      console.log("price of weth", ethers.utils.formatEther(priceOfWeth));
      console.log("wethInFund", ethers.utils.formatEther(wethInFund));
      const price = await valuer.calculateFundValuation(
        fund.address,
        addresses.tokens.WETH
      );
      console.log("fund value", ethers.utils.formatEther(price));

      expect(price.mul(10000)).to.equal(ethers.utils.parseEther("0.01"));
    });
  });
});
