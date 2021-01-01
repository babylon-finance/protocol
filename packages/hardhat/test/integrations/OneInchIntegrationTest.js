const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { impersonateAddress } = require("../../utils/rpc");
const { deployFolioFixture } = require("../fixtures/ControllerFixture");
const addresses = require("../../utils/addresses");
const { EMPTY_BYTES } = require("../../utils/constants");

const { loadFixture } = waffle;

describe("OneInchTradeIntegration", function() {
  let system;
  let oneInchIntegration;
  let fund;

  beforeEach(async () => {
    system = await loadFixture(deployFolioFixture);
    oneInchIntegration = system.integrations.oneInchTradeIntegration;
    fund = system.funds.one;
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await system.folioController.deployed();
      const deployedKyber = await oneInchIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedKyber).to.equal(true);
    });
  });

  describe("Trading", function() {
    let daiToken;
    let usdcToken;
    let whaleSigner;
    const daiWhaleAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";

    beforeEach(async () => {
      whaleSigner = await impersonateAddress(daiWhaleAddress);
      daiToken = await ethers.getContractAt("IERC20", addresses.tokens.DAI);
      usdcToken = await ethers.getContractAt("IERC20", addresses.tokens.USDC);
    });

    it("trade dai to usdc", async function() {
      expect(
        await daiToken
          .connect(whaleSigner)
          .transfer(fund.address, ethers.utils.parseEther("100"), {
            gasPrice: 0
          })
      );
      expect(await daiToken.balanceOf(fund.address)).to.equal(
        ethers.utils.parseEther("100")
      );
      await fund.trade(
        "1inch",
        addresses.tokens.DAI,
        ethers.utils.parseEther("100"),
        usdcToken.address,
        ethers.utils.parseEther("90") / 10 ** 12,
        EMPTY_BYTES,
        { gasPrice: 0 }
      );
      expect(await daiToken.balanceOf(fund.address)).to.equal(0);
      expect(await usdcToken.balanceOf(fund.address)).to.be.gt(
        ethers.utils.parseEther("97") / 10 ** 12
      );
    });
  });
});
