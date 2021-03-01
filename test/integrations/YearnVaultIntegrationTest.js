const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { impersonateAddress } = require("../../utils/rpc");
const { deployFolioFixture } = require("../fixtures/ControllerFixture");
const addresses = require("../../utils/addresses");
const { ADDRESS_ZERO } = require("../../utils/constants");

const { loadFixture } = waffle;

describe("YearnVaultIntegrationTest", function() {
  let system;
  let yearnVaultIntegration;
  let community;
  let userSigner3;

  beforeEach(async () => {
    system = await loadFixture(deployFolioFixture);
    yearnVaultIntegration = system.integrations.yearnVaultIntegration;
    userSigner3 = system.signer3;
    community = system.communitys.one;
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await system.babController.deployed();
      const deployedYearn = await yearnVaultIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedYearn).to.equal(true);
    });
  });

  describe("Yearn Vaults", function() {
    let daiToken;
    let wethToken;
    let whaleSigner;
    let whaleWeth;
    let yearnDaiVault;

    beforeEach(async () => {
      whaleSigner = await impersonateAddress(addresses.holders.DAI);
      whaleWeth = await impersonateAddress(addresses.holders.WETH);
      daiToken = await ethers.getContractAt("IERC20", addresses.tokens.DAI);
      wethToken = await ethers.getContractAt("IERC20", addresses.tokens.WETH);
      yearnDaiVault = await ethers.getContractAt(
        "IVault",
        addresses.yearn.vaults.ydai
      );
    });

    it("check that a valid yearn vault is valid", async function() {
      expect(
        await yearnVaultIntegration.isInvestment(addresses.yearn.vaults.ydai)
      ).to.equal(true);
    });

    it("check that an invalid vault is not valid", async function() {
      await expect(yearnVaultIntegration.isInvestment(ADDRESS_ZERO)).to.be
        .reverted;
    });

    it("can enter and exit the yearn dai vault", async function() {
      // expect(
      //   await daiToken
      //     .connect(whaleSigner)
      //     .transfer(community.address, ethers.utils.parseEther("1000"), {
      //       gasPrice: 0
      //     })
      // );
      // expect(await daiToken.balanceOf(community.address)).to.equal(
      //   ethers.utils.parseEther("1000")
      // );
      await community
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      const amountToDeposit = ethers.utils.parseEther("1000");
      const sharePrice = await yearnDaiVault.getPricePerFullShare();
      const expectedYShares = amountToDeposit.div(sharePrice);

      const yearnAbi = yearnVaultIntegration.interface;
      const data = yearnAbi.encodeFunctionData(
        yearnAbi.functions["enterInvestment(address,uint256,address,uint256)"],
        [
          yearnDaiVault.address,
          expectedYShares,
          daiToken.address,
          ethers.utils.parseEther("100")
        ]
      );

      await community.callIntegration(
        yearnVaultIntegration.address,
        ethers.utils.parseEther("0"),
        data,
        [daiToken.address],
        [ethers.utils.parseEther("100")],
        {
          gasPrice: 0
        }
      );

      console.log("price", ethers.utils.formatEther(sharePrice));
      console.log(
        "balance",
        ethers.utils.formatEther(await yearnDaiVault.balanceOf(community.address))
      );
      console.log("yshares to receive", expectedYShares.toString());
      expect(await yearnDaiVault.balanceOf(community.address)).to.be.gte(
        expectedYShares
      );

      const dataExit = yearnAbi.encodeFunctionData(
        yearnAbi.functions["exitInvestment(address,uint256,address,uint256)"],
        [
          yearnDaiVault.address,
          await yearnDaiVault.balanceOf(community.address),
          daiToken.address,
          ethers.utils.parseEther("99")
        ]
      );

      await community.callIntegration(
        yearnVaultIntegration.address,
        ethers.utils.parseEther("0"),
        dataExit,
        [],
        [],
        {
          gasPrice: 0
        }
      );

      expect(await yearnDaiVault.balanceOf(community.address)).to.equal(0);
      expect(await daiToken.balanceOf(community.address)).to.be.gt(
        ethers.utils.parseEther("99")
      );
    });
  });
});
