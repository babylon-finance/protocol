const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { impersonateAddress } = require("../../utils/rpc");
const { deployFolioFixture } = require("../fixtures/FolioController");
const addresses = require("../../utils/addresses");

const { loadFixture } = waffle;

describe("AaveIntegration", function() {
  let system;

  beforeEach(async () => {
    system = await loadFixture(deployFolioFixture);
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await system.controller.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe("Aave StableDebt", function() {
    let aaveBorrowing;
    let daiToken;
    let usdcToken;
    let lendingPool;
    let dataProvider;
    let whaleSigner;
    const daiWhaleAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";

    beforeEach(async () => {
      whaleSigner = await impersonateAddress(daiWhaleAddress);
      const AaveIntegration = await ethers.getContractFactory(
        "AaveIntegration",
        system.owner
      );
      aaveBorrowing = await AaveIntegration.deploy(system.owner.getAddress());
      lendingPool = await ethers.getContractAt(
        "ILendingPool",
        addresses.aave.lendingPool
      );
      dataProvider = await ethers.getContractAt(
        "IProtocolDataProvider",
        addresses.aave.dataProvider
      );
      daiToken = await ethers.getContractAt("IERC20", addresses.tokens.DAI);
      usdcToken = await ethers.getContractAt("IERC20", addresses.tokens.USDC);
    });

    it("can deposit collateral", async function() {
      expect(await daiToken.balanceOf(system.owner.getAddress())).to.equal(0);
      expect(await daiToken.balanceOf(whaleSigner.getAddress())).to.not.equal(
        0
      );
      expect(
        await daiToken
          .connect(whaleSigner)
          .transfer(system.owner.getAddress(), ethers.utils.parseEther("10"), {
            gasPrice: 0
          })
      );
      expect(await daiToken.balanceOf(system.owner.getAddress())).to.not.equal(
        0
      );
      expect(
        await daiToken.approve(
          aaveBorrowing.address,
          ethers.utils.parseEther("10")
        )
      );
      expect(
        await daiToken.allowance(
          system.owner.getAddress(),
          aaveBorrowing.address
        )
      ).to.equal(ethers.utils.parseEther("10"));
      expect(
        await aaveBorrowing.depositCollateral(
          daiToken.address,
          ethers.utils.parseEther("10")
        )
      );
      expect(await daiToken.balanceOf(aaveBorrowing.address)).to.equal(0);
    });

    it("checks that the dai/usdc pair works", async function() {
      let assetData = await dataProvider.getReserveConfigurationData(
        daiToken.address
      );
      let canBeUsedAsCollateral = true;
      let canBeBorrowed = true;
      if (!assetData.usageAsCollateralEnabled) {
        console.log(`dai is not enabled for use as collateral`);
        canBeUsedAsCollateral = false;
      }
      if (!assetData.isActive) {
        console.log(`dai is not active`);
        canBeUsedAsCollateral = false;
      }
      if (assetData.isFrozen) {
        console.log(`dai is frozen`);
        canBeUsedAsCollateral = false;
      }
      assetData = await dataProvider.getReserveConfigurationData(
        usdcToken.address
      );
      if (!assetData.borrowingEnabled) {
        console.log(`usdc is not enabled for borrowing`);
        canBeBorrowed = false;
      }
      if (!assetData.stableBorrowRateEnabled) {
        console.log(`usdc is not enabled for stable borrowing`);
        canBeBorrowed = false;
      }
      if (!assetData.isActive) {
        console.log(`usdc is not active`);
        canBeBorrowed = false;
      }
      if (assetData.isFrozen) {
        console.log(`usdc is frozen`);
        canBeBorrowed = false;
      }
      // if (assetData.availableLiquidity.lt(delegatedAmount)) {
      //   console.log(`liquidity for ${loanAsset} is not sufficient`));
      //   canBeBorrowed = false;
      // }
      expect(canBeBorrowed).to.equal(true);
      expect(canBeUsedAsCollateral).to.equal(true);
    });

    it("can borrow usdc after depositing dai", async function() {
      expect(
        await daiToken
          .connect(whaleSigner)
          .transfer(
            system.owner.getAddress(),
            ethers.utils.parseEther("1000"),
            {
              gasPrice: 0
            }
          )
      );
      expect(
        await daiToken.approve(
          aaveBorrowing.address,
          ethers.utils.parseEther("1000")
        )
      );
      expect(await daiToken.balanceOf(system.owner.getAddress())).to.equal(
        ethers.utils.parseEther("1000")
      );
      expect(
        await aaveBorrowing.depositCollateral(
          daiToken.address,
          ethers.utils.parseEther("1000")
        )
      );
      expect(await daiToken.balanceOf(aaveBorrowing.address)).to.equal(0);
      expect(await usdcToken.balanceOf(system.owner.getAddress())).to.equal(0);
      expect(
        await aaveBorrowing.borrowAsset(
          usdcToken.address,
          100000000,
          1,
          system.owner.getAddress()
        )
      );
      expect(await usdcToken.balanceOf(system.owner.getAddress())).to.equal(
        100000000
      );
      const things = await lendingPool.getUserAccountData(
        aaveBorrowing.address
      );
      console.log(
        "health factor",
        ethers.utils.formatEther(things.healthFactor)
      );
      console.log(
        "collateral eth",
        ethers.utils.formatEther(things.totalCollateralETH)
      );
      console.log(
        "totalDebtETH eth",
        ethers.utils.formatEther(things.totalDebtETH)
      );
      console.log(
        "availableBorrowsETH eth",
        ethers.utils.formatEther(things.availableBorrowsETH)
      );
    });
  });
});
