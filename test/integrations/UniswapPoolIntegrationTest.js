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
  let community;
  let uniAbi;
  let userSigner3;

  beforeEach(async () => {
    system = await loadFixture(deployFolioFixture);
    uniswapIntegration = system.integrations.uniswapPoolIntegration;
    userSigner3 = system.signer3;
    uniAbi = uniswapIntegration.interface;
    community = system.communitys.one;
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await system.babController.deployed();
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
      await community
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("5"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("5")
        });

      const dataEnter = uniAbi.encodeFunctionData(
        uniAbi.functions["joinPool(address,uint256,address[],uint256[])"],
        [
          addresses.uniswap.pairs.wethdai,
          ethers.utils.parseEther("20"),
          [addresses.tokens.DAI, addresses.tokens.WETH],
          [ethers.utils.parseEther("1000"), ethers.utils.parseEther("1.5")]
        ]
      );

      await community.callIntegration(
        uniswapIntegration.address,
        ethers.utils.parseEther("0"),
        dataEnter,
        [daiToken.address],
        [ethers.utils.parseEther("1000")],
        {
          gasPrice: 0
        }
      );

      expect(await daiWethPair.balanceOf(community.address)).to.be.gt(
        ethers.utils.parseEther("19")
      );

      const dataExit = uniAbi.encodeFunctionData(
        uniAbi.functions["exitPool(address,uint256,address[],uint256[])"],
        [
          addresses.uniswap.pairs.wethdai,
          await daiWethPair.balanceOf(community.address),
          [addresses.tokens.DAI, addresses.tokens.WETH],
          [ethers.utils.parseEther("900"), ethers.utils.parseEther("0.2")]
        ]
      );

      await community.callIntegration(
        uniswapIntegration.address,
        ethers.utils.parseEther("0"),
        dataExit,
        [],
        [],
        {
          gasPrice: 0
        }
      );
      expect(await daiWethPair.balanceOf(community.address)).to.equal(0);
      expect(await daiToken.balanceOf(community.address)).to.be.gt(
        ethers.utils.parseEther("999")
      );
      expect(await wethToken.balanceOf(community.address)).to.be.gt(
        ethers.utils.parseEther("4")
      );
    });
  });
});
