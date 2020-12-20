const { expect } = require("chai");
const { impersonateAddress } = require ('../../utils/rpc');
const addresses = require('../../utils/addresses');

describe("Compound Borrowing Deployment", function () {
  it("Should deploy CompoundBorrowing", async function () {
    const [owner] = await ethers.getSigners();
    const CompoundBorrowing = await ethers.getContractFactory("CompoundBorrowing", owner);
    await CompoundBorrowing.deploy();
  });
});

describe("CompoundBorrowing", async function () {
  const daiWhaleAddress ='0x6B175474E89094C44Da98b954EedeAC495271d0F';
  const whaleSigner = await impersonateAddress(daiWhaleAddress);
  const [owner, addr1, addr2] = await ethers.getSigners();
  const CompoundBorrowing = await ethers.getContractFactory("CompoundBorrowing", owner);

  let daiToken;
  let usdcToken;
  let compoundBorrowing;

  beforeEach(async () => {
    compoundBorrowing = await CompoundBorrowing.deploy();
    daiToken = await ethers.getContractAt("IERC20", addresses.tokens.DAI);
    usdcToken = await ethers.getContractAt("IERC20", addresses.tokens.USDC);
  });

});
