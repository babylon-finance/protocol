const { expect } = require("chai");
const { impersonateAddress } = require ('../../utils/rpc');

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

  beforeEach(async () => {
    collateralToken = await CollateralToken.deploy("Test Collateral", "COL");
    aaveBorrowing = await AaveBorrowing.deploy(owner.getAddress());
    daiToken = await ethers.getContractAt("IERC20", "0x6B175474E89094C44Da98b954EedeAC495271d0F");

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

  });

});
