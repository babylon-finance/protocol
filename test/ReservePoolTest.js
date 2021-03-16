const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');
const { loadFixture } = waffle;
const addresses = require('../utils/addresses');
const { EMPTY_BYTES, ONE_DAY_IN_SECONDS } = require('../utils/constants');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');

describe('ReservePool', function () {
  let controller;
  let reserve;
  let garden;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let weth;

  beforeEach(async () => {
    const { babController, comunities, reservePool, signer1, signer2, owner } = await loadFixture(deployFolioFixture);
    ownerSigner = owner;
    garden = comunities.one;
    userSigner1 = signer1;
    userSigner2 = signer2;
    controller = babController;
    reserve = reservePool;
    weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployedc = await controller.deployed();
      const deployed = await reserve.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedc).to.equal(true);
    });
  });

  describe('Constructor', async function () {
    it('the initial controller must be correct', async function () {
      const controllerA = await reserve.controller();
      await expect(controllerA).to.equal(controller.address);
    });
  });

  describe('Deposit', async function () {
    it('cannot deposit below the limit', async function () {
      await expect(
        reserve.connect(userSigner1).deposit({
          value: ethers.utils.parseEther('0.01'),
        }),
      ).to.be.reverted;
    });

    it('can deposit and receive RBABL tokens', async function () {
      const reserveBalance = await weth.balanceOf(reserve.address);
      expect(reserveBalance).to.equal(0);
      const supplyBefore = await reserve.totalSupply();
      expect(supplyBefore).to.equal(0);
      const valuation = await reserve.getReservePoolValuation();
      expect(valuation).to.equal(0);
      await reserve.connect(userSigner2).deposit({
        value: ethers.utils.parseEther('1'),
      });
      await expect(await weth.balanceOf(reserve.address)).to.equal(ethers.utils.parseEther('1'));
      await expect(await reserve.totalSupply()).to.equal(ethers.utils.parseEther('1'));
      await expect(await reserve.balanceOf(userSigner2.address)).to.equal(ethers.utils.parseEther('1'));
      await expect(await reserve.getReservePoolValuation()).to.equal(ethers.utils.parseEther('1'));
      await expect(await reserve.userTimelock(userSigner2.address)).to.be.gt(0);
    });
  });

  describe('Claim', async function () {
    it('cannot claim before the timelock window expires', async function () {
      await reserve.connect(userSigner2).deposit({
        value: ethers.utils.parseEther('1'),
      });
      await expect(reserve.connect(userSigner2).claim(ethers.utils.parseEther('1'), userSigner2.address)).to.be
        .reverted;
    });

    it('cannot claim after the timelock window more than the deposited', async function () {
      await reserve.connect(userSigner2).deposit({
        value: ethers.utils.parseEther('1'),
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 7 + 1]);
      await expect(reserve.connect(userSigner2).claim(ethers.utils.parseEther('1.01'), userSigner2.address)).to.be
        .reverted;
    });

    it('cannot claim after the timelock window if you deposit again', async function () {
      await reserve.connect(userSigner2).deposit({
        value: ethers.utils.parseEther('1'),
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 7 + 1]);
      await reserve.connect(userSigner2).deposit({
        value: ethers.utils.parseEther('0.1'),
      });
      await expect(reserve.connect(userSigner2).claim(ethers.utils.parseEther('1.01'), userSigner2.address)).to.be
        .reverted;
    });

    it('can claim and redeem RBABL tokens', async function () {
      await reserve.connect(userSigner2).deposit({
        value: ethers.utils.parseEther('1'),
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 7 + 1]);

      await reserve.connect(userSigner2).claim(ethers.utils.parseEther('1'), userSigner1.address);
      const supplyBefore = await reserve.totalSupply();
      expect(supplyBefore).to.equal(0);
    });
  });
});
