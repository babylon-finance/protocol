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
  let fund;

  beforeEach(async () => {
    system = await loadFixture(deployFolioFixture);
    balancerIntegration = system.integrations.balancerIntegration;
    fund = system.funds.one;
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await system.folioController.deployed();
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
        "balancer",
        addresses.balancer.pools.wethdai,
        ethers.utils.parseEther("0.001"),
        await daiWethPool.getFinalTokens(),
        [ethers.utils.parseEther("1000"), ethers.utils.parseEther("10")],
        { gasPrice: 0 }
      );
      expect(await daiWethPool.balanceOf(fund.address)).to.be.eq(
        ethers.utils.parseEther("0.001")
      );
      await fund.exitPool(
        "balancer",
        addresses.balancer.pools.wethdai,
        ethers.utils.parseEther("0.001"),
        await daiWethPool.getFinalTokens(),
        [ethers.utils.parseEther("100"), ethers.utils.parseEther("0.1")],
        { gasPrice: 0 }
      );
    });
  });
});
