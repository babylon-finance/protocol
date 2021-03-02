const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { impersonateAddress } = require("../../utils/rpc");
const { deployFolioFixture } = require("../fixtures/ControllerFixture");
const addresses = require("../../utils/addresses");
const { EMPTY_BYTES } = require("../../utils/constants");

const { loadFixture } = waffle;

describe("KyberTradeIntegration", function() {
  let system;
  let kyberIntegration;
  let kyberAbi;
  let community;
  let userSigner3;

  beforeEach(async () => {
    system = await loadFixture(deployFolioFixture);
    kyberIntegration = system.integrations.kyberTradeIntegration;
    kyberAbi = kyberIntegration.interface;
    userSigner3 = system.signer3;
    community = system.comunities.one;
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
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      expect(await wethToken.balanceOf(community.address)).to.equal(
        ethers.utils.parseEther("1.1")
      );

      const data = kyberAbi.encodeFunctionData(
        kyberAbi.functions["trade(address,uint256,address,uint256,bytes)"],
        [
          addresses.tokens.WETH,
          ethers.utils.parseEther("1"),
          usdcToken.address,
          ethers.utils.parseEther("900") / 10 ** 12,
          EMPTY_BYTES
        ]
      );

      await community.callIntegration(
        kyberIntegration.address,
        ethers.utils.parseEther("0"),
        data,
        [],
        [],
        {
          gasPrice: 0
        }
      );
      expect(await wethToken.balanceOf(community.address)).to.equal(
        ethers.utils.parseEther("0.1")
      );
      expect(await usdcToken.balanceOf(community.address)).to.be.gt(
        ethers.utils.parseEther("97") / 10 ** 12
      );
    });
  });
});
