const { expect } = require("chai");
const superagent = require("superagent");
const { waffle, ethers } = require("hardhat");
const { impersonateAddress } = require("../../utils/rpc");
const { deployFolioFixture } = require("../fixtures/ControllerFixture");
const addresses = require("../../utils/addresses");
const { ZERO } = require("../../utils/constants");

const { loadFixture } = waffle;

describe("OneInchTradeIntegration", function() {
  let system;
  let oneInchIntegration;
  let community;

  beforeEach(async () => {
    system = await loadFixture(deployFolioFixture);
    oneInchIntegration = system.integrations.oneInchTradeIntegration;
    community = system.comunities.one;
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await system.babController.deployed();
      const deployedKyber = await oneInchIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedKyber).to.equal(true);
    });
  });

  describe("Trading", function() {
    let daiToken;
    let usdcToken;
    let whaleSigner;
    let oneInchExchange;
    const daiWhaleAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";

    beforeEach(async () => {
      whaleSigner = await impersonateAddress(daiWhaleAddress);
      daiToken = await ethers.getContractAt("IERC20", addresses.tokens.DAI);
      usdcToken = await ethers.getContractAt("IERC20", addresses.tokens.USDC);
      oneInchExchange = await ethers.getContractAt(
        "IOneInchExchange",
        addresses.oneinch.exchange
      );
    });

    it("trade dai to usdc", async function() {
      expect(
        await daiToken
          .connect(whaleSigner)
          .transfer(community.address, ethers.utils.parseEther("100"), {
            gasPrice: 0
          })
      );
      expect(await daiToken.balanceOf(community.address)).to.equal(
        ethers.utils.parseEther("100")
      );
      // Get the quote
      const quote = await superagent
        .get(`${addresses.api.oneinch}quote`)
        .query({
          fromTokenAddress: daiToken.address,
          toTokenAddress: usdcToken.address,
          amount: 100 * 10 ** 18
        });
      // Get the parts
      // const parts = await oneInchExchange.getExpectedReturn(
      //   daiToken.address,
      //   usdcToken.address,
      //   ethers.utils.parseEther("100"),
      //   1,
      //   0
      // );
      //
      // // Get call data
      // const callData = oneInchExchange.interface.encodeFunctionData(
      //   oneInchExchange.interface.functions[
      //     "swap(address,address,uint256,uint256,uint256[],uint256)"
      //   ],
      //   [
      //     daiToken.address, // Send token
      //     usdcToken.address, // Receive token
      //     ethers.utils.parseEther("100"), // Send quantity
      //     quote.body.toTokenAmount, // Min receive quantity
      //     parts.distribution,
      //     0
      //   ]
      // );
      //
      // await community.trade(
      //   "1inch",
      //   addresses.tokens.DAI,
      //   ethers.utils.parseEther("100"),
      //   usdcToken.address,
      //   quote.body.toTokenAmount,
      //   callData,
      //   { gasPrice: 0 }
      // );
      // expect(await daiToken.balanceOf(community.address)).to.equal(0);
      // console.log(
      //   ethers.utils.formatEther(await usdcToken.balanceOf(community.address))
      // );
      // expect(await usdcToken.balanceOf(community.address)).to.be.gt(
      //   ethers.utils.parseEther("97") / 10 ** 12
      // );
    });
  });
});
