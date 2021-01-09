const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { impersonateAddress } = require("../../utils/rpc");
const { deployFolioFixture } = require("../fixtures/ControllerFixture");
const addresses = require("../../utils/addresses");
const { ADDRESS_ZERO } = require("../../utils/constants");

const { loadFixture } = waffle;

describe("UniswapPoolIntegrationTest", function() {
  let system;
  let uniswapIntegration;
  let fund;

  beforeEach(async () => {
    system = await loadFixture(deployFolioFixture);
    uniswapIntegration = system.integrations.uniswapPoolIntegration;
    fund = system.funds.one;
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await system.folioController.deployed();
      const deployedUni = await uniswapIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedUni).to.equal(true);
    });
  });

  describe("Liquidity Pools", function() {
    let daiToken;
    let wethToken;
    let whaleSigner;
    let whaleWeth;
    let daiWethPair;

    beforeEach(async () => {
      whaleSigner = await impersonateAddress(addresses.holders.DAI);
      whaleWeth = await impersonateAddress(addresses.holders.WETH);
      daiToken = await ethers.getContractAt("IERC20", addresses.tokens.DAI);
      wethToken = await ethers.getContractAt("IERC20", addresses.tokens.WETH);
      daiWethPair = await ethers.getContractAt(
        "IUniswapV2Pair",
        addresses.uniswap.pairs.wethdai
      );
    });

    it("check that a valid pool is valid", async function() {
      expect(
        await uniswapIntegration.isPool(addresses.uniswap.pairs.wethdai)
      ).to.equal(true);
    });

    it("check that an invalid pool is not valid", async function() {
      await expect(uniswapIntegration.isPool(ADDRESS_ZERO)).to.be.reverted;
    });

    it("can enter and exit the weth dai pool", async function() {
      expect(
        await daiToken
          .connect(whaleSigner)
          .transfer(fund.address, ethers.utils.parseEther("1000"), {
            gasPrice: 0
          })
      );
      expect(
        await wethToken
          .connect(whaleWeth)
          .transfer(fund.address, ethers.utils.parseEther("10"), {
            gasPrice: 0
          })
      );
      expect(await daiToken.balanceOf(fund.address)).to.equal(
        ethers.utils.parseEther("1000")
      );
      expect(await wethToken.balanceOf(fund.address)).to.equal(
        ethers.utils.parseEther("10.01")
      );
      await fund.joinPool(
        "uniswap_pool",
        addresses.uniswap.pairs.wethdai,
        ethers.utils.parseEther("20"),
        [addresses.tokens.DAI, addresses.tokens.WETH],
        [ethers.utils.parseEther("1000"), ethers.utils.parseEther("0.9")],
        { gasPrice: 0 }
      );
      expect(await daiWethPair.balanceOf(fund.address)).to.be.gt(
        ethers.utils.parseEther("22")
      );
      await fund.exitPool(
        "uniswap_pool",
        addresses.uniswap.pairs.wethdai,
        await daiWethPair.balanceOf(fund.address),
        [addresses.tokens.DAI, addresses.tokens.WETH],
        [ethers.utils.parseEther("900"), ethers.utils.parseEther("0.7")],
        { gasPrice: 0 }
      );
      expect(await daiWethPair.balanceOf(fund.address)).to.equal(0);
      expect(await daiToken.balanceOf(fund.address)).to.be.gt(
        ethers.utils.parseEther("999")
      );
      expect(await wethToken.balanceOf(fund.address)).to.be.gt(
        ethers.utils.parseEther("10.00")
      );
    });
  });
});
