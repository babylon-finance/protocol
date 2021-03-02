const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { impersonateAddress } = require("../../utils/rpc");
const { deployFolioFixture } = require("../fixtures/ControllerFixture");
const addresses = require("../../utils/addresses");
const { ADDRESS_ZERO } = require("../../utils/constants");

const { loadFixture } = waffle;

describe("BalancerIntegrationTest", function() {
  let system;
  let balancerIntegration;
  let balancerAbi;
  let community;
  let userSigner3;

  beforeEach(async () => {
    system = await loadFixture(deployFolioFixture);
    balancerIntegration = system.integrations.balancerIntegration;
    userSigner3 = system.signer3;
    balancerAbi = balancerIntegration.interface;
    community = system.comunities.one;
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await system.babController.deployed();
      const deployedBalancer = await balancerIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedBalancer).to.equal(true);
    });
  });

  describe("Liquidity Pools", function() {
    let daiToken;
    let wethToken;
    let whaleSigner;
    let whaleWeth;
    let daiWethPool;

    beforeEach(async () => {
      whaleSigner = await impersonateAddress(addresses.holders.DAI);
      whaleWeth = await impersonateAddress(addresses.holders.WETH);
      daiToken = await ethers.getContractAt("IERC20", addresses.tokens.DAI);
      wethToken = await ethers.getContractAt("IERC20", addresses.tokens.WETH);
      daiWethPool = await ethers.getContractAt(
        "IBPool",
        addresses.balancer.pools.wethdai
      );
    });

    it("check that a valid pool is valid", async function() {
      expect(
        await balancerIntegration.isPool(addresses.balancer.pools.wethdai)
      ).to.equal(true);
    });

    it("check that an invalid pool is not valid", async function() {
      expect(await balancerIntegration.isPool(ADDRESS_ZERO)).to.equal(false);
    });

    it("can enter and exit the weth dai pool", async function() {
      // expect(
      //   await daiToken
      //     .connect(whaleSigner)
      //     .transfer(community.address, ethers.utils.parseEther("1000"), {
      //       gasPrice: 0
      //     })
      // );

      await community
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("5"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("5")
        });

      const dataEnter = balancerAbi.encodeFunctionData(
        balancerAbi.functions["joinPool(address,uint256,address[],uint256[])"],
        [
          addresses.balancer.pools.wethdai,
          ethers.utils.parseEther("0.001"),
          await daiWethPool.getFinalTokens(),
          [ethers.utils.parseEther("1000"), ethers.utils.parseEther("2")]
        ]
      );

      await community.callIntegration(
        balancerIntegration.address,
        ethers.utils.parseEther("0"),
        dataEnter,
        [daiToken.address],
        [ethers.utils.parseEther("1000")],
        {
          gasPrice: 0
        }
      );

      expect(await daiWethPool.balanceOf(community.address)).to.be.eq(
        ethers.utils.parseEther("0.001")
      );

      const dataExit = balancerAbi.encodeFunctionData(
        balancerAbi.functions["exitPool(address,uint256,address[],uint256[])"],
        [
          addresses.balancer.pools.wethdai,
          ethers.utils.parseEther("0.001"),
          await daiWethPool.getFinalTokens(),
          [ethers.utils.parseEther("100"), ethers.utils.parseEther("0.1")]
        ]
      );

      await community.callIntegration(
        balancerIntegration.address,
        ethers.utils.parseEther("0"),
        dataExit,
        [],
        [],
        {
          gasPrice: 0
        }
      );

      expect(await daiWethPool.balanceOf(community.address)).to.equal(0);
      expect(await daiToken.balanceOf(community.address)).to.be.gt(
        ethers.utils.parseEther("999")
      );
      expect(await wethToken.balanceOf(community.address)).to.be.gt(
        ethers.utils.parseEther("4.00")
      );
    });
  });
});
