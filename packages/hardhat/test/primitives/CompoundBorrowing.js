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

  let cethToken;
  let daiToken;
  let cdaiToken;
  let cusdcToken;
  let compoundBorrowing;

  beforeEach(async () => {
    compoundBorrowing = await CompoundBorrowing.deploy();
    daiToken = await ethers.getContractAt("IERC20", addresses.tokens.DAI);
    cdaiToken = await ethers.getContractAt("ICToken", addresses.tokens.CDAI);
    cusdcToken = await ethers.getContractAt("ICToken", addresses.tokens.CUSDC);
    cethToken = await ethers.getContractAt("ICEther", addresses.tokens.CETH);
  });

  describe("Compound Borrowing/Lending", function () {

    it("can supply ether", async function () {
      expect(await cethToken.balanceOf(compoundBorrowing.address)).to.equal(0);
      await expect(() => owner.sendTransaction({ to: compoundBorrowing.address, gasPrice: 0, value: 1000000000 }))
        .to.changeEtherBalance(owner, -1000000000);
      await compoundBorrowing.supply(addresses.tokens.CETH, ethers.utils.parseEther('1'), { value: ethers.utils.parseEther('1') });
      const balance = await cethToken.balanceOf(compoundBorrowing.address);
      expect(balance).to.be.gt(0);
    });

    it("can supply erc20", async function () {
      expect(await daiToken.connect(whaleSigner).transfer(compoundBorrowing.address, ethers.utils.parseEther('1000'), { gasPrice: 0}));
      expect(await daiToken.connect(whaleSigner).transfer(owner.getAddress(), ethers.utils.parseEther('1000'), { gasPrice: 0}));
      expect(await cdaiToken.balanceOf(compoundBorrowing.address)).to.equal(0);
      expect(await daiToken.balanceOf(compoundBorrowing.address)).to.equal(ethers.utils.parseEther('1000'));
      expect(await daiToken.balanceOf(owner.getAddress())).to.equal(ethers.utils.parseEther('1000'));
      await expect(() => owner.sendTransaction({ to: compoundBorrowing.address, gasPrice: 0, value: 1000000000 }))
        .to.changeEtherBalance(owner, -1000000000);
      expect(await compoundBorrowing.supply(addresses.tokens.CDAI, ethers.utils.parseEther('100'), { gasPrice: 0 }));
      const balance = await cdaiToken.balanceOf(compoundBorrowing.address);
      expect(balance).to.be.gt(0);
    });

    it("can supply ether and borrow dai", async function () {
      expect(await cethToken.balanceOf(compoundBorrowing.address)).to.equal(0);
      await expect(() => owner.sendTransaction({ to: compoundBorrowing.address, gasPrice: 0, value: 1000000000 }))
        .to.changeEtherBalance(owner, -1000000000);
      await compoundBorrowing.supply(addresses.tokens.CETH, ethers.utils.parseEther('10'), { value: ethers.utils.parseEther('10') });
      let balance = await cethToken.balanceOf(compoundBorrowing.address);
      expect(balance).to.be.gt(0);
      expect(await compoundBorrowing.enterMarketsAndApproveCTokens([cdaiToken.address, cethToken.address]));
      expect(await cdaiToken.balanceOf(compoundBorrowing.address)).to.equal(0);
      expect(await compoundBorrowing.borrow(cdaiToken.address, ethers.utils.parseEther('10')));
      balance = await cdaiToken.borrowBalanceCurrent(compoundBorrowing.address);
      expect(balance).to.be.gt(0);
    });

    it("can supply dai and borrow dai", async function () {
      expect(await daiToken.connect(whaleSigner).transfer(compoundBorrowing.address, ethers.utils.parseEther('1000'), { gasPrice: 0}));
      expect(await daiToken.connect(whaleSigner).transfer(owner.getAddress(), ethers.utils.parseEther('1000'), { gasPrice: 0}));
      expect(await cdaiToken.balanceOf(compoundBorrowing.address)).to.equal(0);
      expect(await daiToken.balanceOf(compoundBorrowing.address)).to.equal(ethers.utils.parseEther('1000'));
      expect(await daiToken.balanceOf(owner.getAddress())).to.equal(ethers.utils.parseEther('2000'));
      await expect(() => owner.sendTransaction({ to: compoundBorrowing.address, gasPrice: 0, value: 1000000000 }))
        .to.changeEtherBalance(owner, -1000000000);
      expect(await compoundBorrowing.supply(addresses.tokens.CDAI, ethers.utils.parseEther('100'), { gasPrice: 0 }));
      let balance = await cdaiToken.balanceOf(compoundBorrowing.address);
      expect(balance).to.be.gt(0);
      expect(await compoundBorrowing.enterMarketsAndApproveCTokens([cdaiToken.address, cusdcToken.address]));
      expect(await cdaiToken.balanceOf(compoundBorrowing.address)).to.be.gt(0);
      expect(await compoundBorrowing.borrow(cdaiToken.address, ethers.utils.parseEther('1')));
      balance = await cdaiToken.borrowBalanceCurrent(compoundBorrowing.address);
      expect(balance).to.be.gt(0);
    });

  })

});
