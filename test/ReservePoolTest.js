const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { loadFixture } = waffle;
const addresses = require('../utils/addresses');
const { EMPTY_BYTES, ONE_DAY_IN_SECONDS } = require('../utils/constants');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');

describe('ReservePool', function () {
  let babController;
  let reservePool;
  let signer1;
  let signer2;
  let weth;

  beforeEach(async () => {
    ({ babController, reservePool, signer1, signer2 } = await loadFixture(deployFolioFixture));
    weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployedc = await babController.deployed();
      const deployed = await reservePool.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedc).to.equal(true);
    });
  });

  describe('Constructor', async function () {
    it('the initial controller must be correct', async function () {
      const controllerA = await reservePool.controller();
      await expect(controllerA).to.equal(babController.address);
    });
  });

  describe('Deposit', async function () {
    it('cannot deposit below the limit', async function () {
      await expect(
        reservePool.connect(signer1).deposit({
          value: ethers.utils.parseEther('0.01'),
        }),
      ).to.be.reverted;
    });

    it('can deposit and receive RBABL tokens', async function () {
      const reserveBalance = await weth.balanceOf(reservePool.address);
      expect(reserveBalance).to.equal(0);
      const supplyBefore = await reservePool.totalSupply();
      expect(supplyBefore).to.equal(0);
      const valuation = await reservePool.getReservePoolValuation();
      expect(valuation).to.equal(0);
      await reservePool.connect(signer2).deposit({
        value: ethers.utils.parseEther('1'),
      });
      await expect(await weth.balanceOf(reservePool.address)).to.equal(ethers.utils.parseEther('1'));
      await expect(await reservePool.totalSupply()).to.equal(ethers.utils.parseEther('1'));
      await expect(await reservePool.balanceOf(signer2.address)).to.equal(ethers.utils.parseEther('1'));
      await expect(await reservePool.getReservePoolValuation()).to.equal(ethers.utils.parseEther('1'));
      await expect(await reservePool.userTimelock(signer2.address)).to.be.gt(0);
    });
  });

  describe('Claim', async function () {
    it('cannot claim before the timelock window expires', async function () {
      await reservePool.connect(signer2).deposit({
        value: ethers.utils.parseEther('1'),
      });
      await expect(reservePool.connect(signer2).claim(ethers.utils.parseEther('1'), signer2.address)).to.be.reverted;
    });

    it('cannot claim after the timelock window more than the deposited', async function () {
      await reservePool.connect(signer2).deposit({
        value: ethers.utils.parseEther('1'),
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 7 + 1]);
      await expect(reservePool.connect(signer2).claim(ethers.utils.parseEther('1.01'), signer2.address)).to.be.reverted;
    });

    it('cannot claim after the timelock window if you deposit again', async function () {
      await reservePool.connect(signer2).deposit({
        value: ethers.utils.parseEther('1'),
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 7 + 1]);
      await reservePool.connect(signer2).deposit({
        value: ethers.utils.parseEther('0.1'),
      });
      await expect(reservePool.connect(signer2).claim(ethers.utils.parseEther('1.01'), signer2.address)).to.be.reverted;
    });

    it('can claim and redeem RBABL tokens', async function () {
      await reservePool.connect(signer2).deposit({
        value: ethers.utils.parseEther('1'),
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 7 + 1]);

      await reservePool.connect(signer2).claim(ethers.utils.parseEther('1'), signer1.address);
      const supplyBefore = await reservePool.totalSupply();
      expect(supplyBefore).to.equal(0);
    });
  });
});
