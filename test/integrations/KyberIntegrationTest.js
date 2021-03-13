const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
// const { impersonateAddress } = require("../../utils/rpc");
const { deployFolioFixture } = require("../fixtures/ControllerFixture");
const addresses = require("../../utils/addresses");
const { EMPTY_BYTES, ONE_DAY_IN_SECONDS } = require("../../utils/constants");

const { loadFixture } = waffle;

describe("KyberTradeIntegration", function() {
  let system;
  let kyberIntegration;
  let kyberAbi;
  let community;
  let userSigner1;
  let userSigner3;
  let idea;

  beforeEach(async () => {
    system = await loadFixture(deployFolioFixture);
    kyberIntegration = system.integrations.kyberTradeIntegration;
    kyberAbi = kyberIntegration.interface;
    userSigner3 = system.signer3;
    userSigner1 = system.signer1;
    community = system.comunities.one;
    idea = system.ideas[0];
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await system.babController.deployed();
      const deployedKyber = await kyberIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedKyber).to.equal(true);
    });
  });

  describe("Trading", function() {
    let wethToken;
    let usdcToken;

    beforeEach(async () => {
      wethToken = await ethers.getContractAt("IERC20", addresses.tokens.WETH);
      usdcToken = await ethers.getContractAt("IERC20", addresses.tokens.USDC);
    });

    it("trade weth to usdc", async function() {
      await community
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("2"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("2")
        });
      await community
        .connect(userSigner1)
        .deposit(ethers.utils.parseEther("2"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("2")
        });
      expect(await wethToken.balanceOf(community.address)).to.equal(
        ethers.utils.parseEther("4.1")
      );

      const dataEnter = kyberAbi.encodeFunctionData(
        kyberAbi.functions["trade(address,uint256,address,uint256,bytes)"],
        [
          addresses.tokens.WETH,
          ethers.utils.parseEther("1"),
          usdcToken.address,
          ethers.utils.parseEther("900") / 10 ** 12,
          EMPTY_BYTES
        ]
      );

      const dataExit = kyberAbi.encodeFunctionData(
        kyberAbi.functions["trade(address,uint256,address,uint256,bytes)"],
        [
          usdcToken.address,
          ethers.utils.parseEther("900") / 10 ** 12,
          addresses.tokens.WETH,
          ethers.utils.parseEther("0.1"),
          EMPTY_BYTES
        ]
      );

      await idea
        .connect(userSigner1)
        .setIntegrationData(
          kyberIntegration.address,
          dataEnter,
          dataExit,
          [],
          [],
          {
            gasPrice: 0
          }
        );

      await idea
        .connect(userSigner3)
        .curateIdea(await community.balanceOf(userSigner3.getAddress()));

      ethers.provider.send("evm_increaseTime", [ONE_DAY_IN_SECONDS * 2]);

      await idea.executeInvestment(ethers.utils.parseEther("1"), {
        gasPrice: 0
      });

      expect(await wethToken.balanceOf(idea.address)).to.equal(
        ethers.utils.parseEther("0")
      );
      expect(await usdcToken.balanceOf(idea.address)).to.be.gt(
        ethers.utils.parseEther("97") / 10 ** 12
      );

      ethers.provider.send("evm_increaseTime", [ONE_DAY_IN_SECONDS * 90]);

      // await idea.finalizeInvestment({ gasPrice: 0 });
      // expect(await usdcToken.balanceOf(idea.address)).to.equal(0);
    });
  });
});
