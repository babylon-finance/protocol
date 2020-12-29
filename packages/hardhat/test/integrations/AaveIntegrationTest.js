const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { impersonateAddress } = require("../../utils/rpc");
const { deployFolioFixture } = require("../fixtures/ControllerFixture");
const addresses = require("../../utils/addresses");

const { loadFixture } = waffle;

describe("AaveIntegration", function() {
  let system;
  let aaveIntegration;
  let fund;

  beforeEach(async () => {
    system = await loadFixture(deployFolioFixture);
    aaveIntegration = system.integrations.aaveIntegration;
    fund = system.funds.one;
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await system.folioController.deployed();
      const deployedAave = await aaveIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedAave).to.equal(true);
    });
  });

  describe("Aave StableDebt", function() {
    let daiToken;
    let usdcToken;
    let lendingPool;
    let dataProvider;
    let whaleSigner;
    const daiWhaleAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";

    async function printUserAccount(asset) {
      const things = await lendingPool.getUserAccountData(
        aaveIntegration.address
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
      if (asset) {
        const res = await dataProvider.getUserReserveData(
          asset,
          aaveIntegration.address
        );
        console.log("res", res);
      }
    }

    beforeEach(async () => {
      whaleSigner = await impersonateAddress(daiWhaleAddress);
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

    // it("can deposit collateral", async function() {
    //   expect(await daiToken.balanceOf(system.owner.getAddress())).to.equal(0);
    //   expect(await daiToken.balanceOf(whaleSigner.getAddress())).to.not.equal(
    //     0
    //   );
    //   expect(
    //     await daiToken
    //       .connect(whaleSigner)
    //       .transfer(system.owner.getAddress(), ethers.utils.parseEther("10"), {
    //         gasPrice: 0
    //       })
    //   );
    //   expect(await daiToken.balanceOf(system.owner.getAddress())).to.not.equal(
    //     0
    //   );
    //   expect(
    //     await daiToken.approve(
    //       aaveIntegration.address,
    //       ethers.utils.parseEther("10")
    //     )
    //   );
    //   expect(
    //     await daiToken.allowance(
    //       system.owner.getAddress(),
    //       aaveIntegration.address
    //     )
    //   ).to.equal(ethers.utils.parseEther("10"));
    //   await aaveIntegration
    //     .connect(system.owner)
    //     .depositCollateral(daiToken.address, ethers.utils.parseEther("10"), {
    //       gasPrice: 0
    //     });
    //   expect(await daiToken.balanceOf(system.owner.address)).to.equal(0);
    //   // await printUserAccount(daiToken.address);
    //   // console.log(await aaveIntegration.getBorrowBalance(daiToken.address));
    // });
    //
    // it("checks that the dai/usdc pair works", async function() {
    //   let assetData = await dataProvider.getReserveConfigurationData(
    //     daiToken.address
    //   );
    //   let canBeUsedAsCollateral = true;
    //   let canBeBorrowed = true;
    //   if (!assetData.usageAsCollateralEnabled) {
    //     console.log(`dai is not enabled for use as collateral`);
    //     canBeUsedAsCollateral = false;
    //   }
    //   if (!assetData.isActive) {
    //     console.log(`dai is not active`);
    //     canBeUsedAsCollateral = false;
    //   }
    //   if (assetData.isFrozen) {
    //     console.log(`dai is frozen`);
    //     canBeUsedAsCollateral = false;
    //   }
    //   assetData = await dataProvider.getReserveConfigurationData(
    //     usdcToken.address
    //   );
    //   if (!assetData.borrowingEnabled) {
    //     console.log(`usdc is not enabled for borrowing`);
    //     canBeBorrowed = false;
    //   }
    //   if (!assetData.stableBorrowRateEnabled) {
    //     console.log(`usdc is not enabled for stable borrowing`);
    //     canBeBorrowed = false;
    //   }
    //   if (!assetData.isActive) {
    //     console.log(`usdc is not active`);
    //     canBeBorrowed = false;
    //   }
    //   if (assetData.isFrozen) {
    //     console.log(`usdc is frozen`);
    //     canBeBorrowed = false;
    //   }
    //   // if (assetData.availableLiquidity.lt(delegatedAmount)) {
    //   //   console.log(`liquidity for ${loanAsset} is not sufficient`));
    //   //   canBeBorrowed = false;
    //   // }
    //   expect(canBeBorrowed).to.equal(true);
    //   expect(canBeUsedAsCollateral).to.equal(true);
    // });

    // it("can borrow usdc after depositing dai", async function() {
    //   expect(
    //     await daiToken
    //       .connect(whaleSigner)
    //       .transfer(
    //         system.owner.getAddress(),
    //         ethers.utils.parseEther("1000"),
    //         {
    //           gasPrice: 0
    //         }
    //       )
    //   );
    //   expect(
    //     await daiToken.approve(
    //       aaveIntegration.address,
    //       ethers.utils.parseEther("1000")
    //     )
    //   );
    //   expect(await daiToken.balanceOf(system.owner.getAddress())).to.equal(
    //     ethers.utils.parseEther("1000")
    //   );
    //   expect(
    //     await aaveIntegration.depositCollateral(
    //       daiToken.address,
    //       ethers.utils.parseEther("1000")
    //     )
    //   );
    //   console.log('aa');
    //   expect(await daiToken.balanceOf(aaveIntegration.address)).to.equal(0);
    //   expect(await usdcToken.balanceOf(system.owner.getAddress())).to.equal(0);
    //   expect(await aaveIntegration.borrow(usdcToken.address, 100000000));
    //   // printUserAccount();
    //   expect(await usdcToken.balanceOf(aaveIntegration.address)).to.equal(
    //     100000000
    //   );
    // });
  });
});
