const { expect } = require("chai");

describe("Aave Borrowing Deployment", function () {
  it("Should deploy AaveBorrowing", async function () {
    const [owner] = await ethers.getSigners();
    const AaveBorrowing = await ethers.getContractFactory("AaveBorrowing", owner);
    await AaveBorrowing.deploy(owner.getAddress());
  });
});

describe("AaveBorrowing", async function () {
  const [owner, addr1, addr2] = await ethers.getSigners();
  const AaveBorrowing = await ethers.getContractFactory("AaveBorrowing", owner);

  beforeEach(async () => {
    aaveBorrowing = await AaveBorrowing.deploy(owner.getAddress());
  });

  let aaveBorrowing;

  describe("StableDebt", function () {
    it("should set the owner", async function () {
      expect(await aaveBorrowing.owner()).to.equal(await owner.getAddress());
    });
  });

});
