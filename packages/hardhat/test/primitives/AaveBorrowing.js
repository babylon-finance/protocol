const { expect } = require("chai");
const { impersonateAddress } = require ('../../utils/rpc');
const addresses = require('../../utils/addresses');

describe("Aave Borrowing Deployment", function () {
  it("Should deploy AaveBorrowing", async function () {
    const [owner] = await ethers.getSigners();
    const AaveBorrowing = await ethers.getContractFactory("AaveBorrowing", owner);
    await AaveBorrowing.deploy(owner.getAddress());
  });
});

describe("AaveBorrowing", async function () {
  const daiWhaleAddress ='0x6B175474E89094C44Da98b954EedeAC495271d0F';
  const whaleSigner = await impersonateAddress(daiWhaleAddress);
  const [owner, addr1, addr2] = await ethers.getSigners();
  const AaveBorrowing = await ethers.getContractFactory("AaveBorrowing", owner);
  const CollateralToken = await ethers.getContractFactory("FundToken", owner);

  let aaveBorrowing;
  let collateralToken;
  let daiToken;
  let lendingPool;
  let dataProvider;

  beforeEach(async () => {
    collateralToken = await CollateralToken.deploy("Test Collateral", "COL");
    aaveBorrowing = await AaveBorrowing.deploy(owner.getAddress());
    lendingPool = await ethers.getContractAt('ILendingPool', addresses.aave.lendingPool);
    dataProvider = await ethers.getContractAt('IProtocolDataProvider', addresses.aave.dataProvider);
    daiToken = await ethers.getContractAt("IERC20", addresses.tokens.DAI);
    usdcToken = await ethers.getContractAt("IERC20", addresses.tokens.USDC);

  });

  describe("StableDebt", function () {
    it("should set the owner", async function () {
      expect(await aaveBorrowing.owner()).to.equal(await owner.getAddress());
    });

    it("can deposit collateral", async function () {
      expect(await daiToken.balanceOf(owner.getAddress())).to.equal(0);
      expect(await daiToken.balanceOf(whaleSigner.getAddress())).to.not.equal(0);
      expect(await daiToken.connect(whaleSigner).transfer(owner.getAddress(), ethers.utils.parseEther('10'), { gasPrice: 0}));
      expect(await daiToken.balanceOf(owner.getAddress())).to.not.equal(0);
      expect(await daiToken.approve(aaveBorrowing.address, ethers.utils.parseEther('10')));
      expect(await daiToken.allowance(owner.getAddress(), aaveBorrowing.address)).to.equal(ethers.utils.parseEther('10'));
      expect(await aaveBorrowing.depositCollateral(daiToken.address, ethers.utils.parseEther('10')));
      expect(await daiToken.balanceOf(aaveBorrowing.address)).to.equal(0);
    });

    it("checks that the dai/usdc pair works", async function () {
      let assetData = await dataProvider.getReserveConfigurationData(daiToken.address);
      let canBeUsedAsCollateral = true;
      let canBeBorrowed = true;
      if (!assetData.usageAsCollateralEnabled) {
        console.log(`${depositAsset} is not enabled for use as collateral`);
        canBeUsedAsCollateral = false;
      }
      if (!assetData.isActive) {
        console.log(`${depositAsset} is not active`);
        canBeUsedAsCollateral = false;
      };
      if (assetData.isFrozen) {
        console.log(`${depositAsset} is frozen`);
        canBeUsedAsCollateral = false;
      };
      assetData = await dataProvider.getReserveConfigurationData(usdcToken.address);
      if (!assetData.borrowingEnabled) {
        console.log(`${loanAsset} is not enabled for borrowing`);
        canBeBorrowed = false;
      };
      if (!assetData.stableBorrowRateEnabled) {
        console.log(`${loanAsset} is not enabled for stable borrowing`);
        canBeBorrowed = false;
      };
      if (!assetData.isActive) {
        console.log(`${loanAsset} is not active`);
        canBeBorrowed = false;
      };
      if (assetData.isFrozen) {
        console.log(`${loanAsset} is frozen`);
        canBeBorrowed = false;
      };
      // if (assetData.availableLiquidity.lt(delegatedAmount)) {
      //   console.log(`liquidity for ${loanAsset} is not sufficient`));
      //   canBeBorrowed = false;
      // }
      expect(canBeBorrowed).to.equal(true);
      expect(canBeUsedAsCollateral).to.equal(true);
    })

    it("can borrow an asset after depositing collateral", async function () {
      expect(await daiToken.connect(whaleSigner).transfer(owner.getAddress(), ethers.utils.parseEther('1000'), { gasPrice: 0}));
      expect(await daiToken.approve(aaveBorrowing.address, ethers.utils.parseEther('1000')));
      expect(await daiToken.balanceOf(owner.getAddress())).to.equal(ethers.utils.parseEther('1000'));
      expect(await aaveBorrowing.depositCollateral(daiToken.address, ethers.utils.parseEther('1000')));
      expect(await daiToken.balanceOf(aaveBorrowing.address)).to.equal(0);
      expect(await usdcToken.balanceOf(owner.getAddress())).to.equal(0);
      expect(await aaveBorrowing.borrowAsset(usdcToken.address, 100, 1, owner.getAddress()));
      expect(await usdcToken.balanceOf(owner.getAddress())).to.equal(100);
    });

  });

});
