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
  let fund;
  let userSigner3;

  beforeEach(async () => {
    system = await loadFixture(deployFolioFixture);
    kyberIntegration = system.integrations.kyberTradeIntegration;
    userSigner3 = system.signer3;
    fund = system.funds.one;
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await system.folioController.deployed();
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
      await fund
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      // expect(
      //   await daiToken
      //     .connect(whaleSigner)
      //     .transfer(fund.address, ethers.utils.parseEther("100"), {
      //       gasPrice: 0
      //     })
      // );
      expect(await wethToken.balanceOf(fund.address)).to.equal(
        ethers.utils.parseEther("1.1")
      );
      await fund.trade(
        "kyber",
        addresses.tokens.WETH,
        ethers.utils.parseEther("1"),
        usdcToken.address,
        ethers.utils.parseEther("900") / 10 ** 12,
        EMPTY_BYTES,
        { gasPrice: 0 }
      );
      expect(await wethToken.balanceOf(fund.address)).to.equal(
        ethers.utils.parseEther("0.1")
      );
      expect(await usdcToken.balanceOf(fund.address)).to.be.gt(
        ethers.utils.parseEther("97") / 10 ** 12
      );
    });
  });
});
