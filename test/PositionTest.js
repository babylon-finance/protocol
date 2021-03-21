const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { loadFixture } = waffle;
const { ONE_DAY_IN_SECONDS } = require('../utils/constants');
const addresses = require('../utils/addresses');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');

describe('Position testing', function () {
  let controller;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let userSigner3;
  let garden1;
  let treasuryD;
  let garden2;
  let weth;

  beforeEach(async () => {
    const { babController, treasury, signer1, signer2, signer3, gardens, integrations, owner } = await loadFixture(
      deployFolioFixture,
    );

    controller = babController;
    treasuryD = treasury;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;
    garden1 = gardens.one;
    garden2 = gardens.two;
    weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Initial Positions', async function () {
    it('when creating a garden the positions are at 0', async function () {
      expect(await garden2.totalContributors()).to.equal(0);
      expect(await garden2.getPrincipal()).to.equal(ethers.utils.parseEther('0'));
      const wethPosition = await garden1.getPrincipal();
      expect(wethPosition).to.be.gt(ethers.utils.parseEther('0'));
      expect(await garden2.totalSupply()).to.equal(ethers.utils.parseEther('0'));
    });

    it('updates weth position accordingly when initializing the garden', async function () {
      expect(await garden1.totalContributors()).to.equal(1);
      expect(await garden1.getPrincipal()).to.equal(ethers.utils.parseEther('0.1'));
      const wethPosition = await garden1.getPrincipal();
      expect(await weth.balanceOf(garden1.address)).to.equal(ethers.utils.parseEther('0.1'));
      expect(wethPosition).to.equal(ethers.utils.parseEther('0.1'));
      expect(await garden1.creator()).to.equal(await userSigner1.getAddress());
      expect(await garden1.balanceOf(userSigner1.getAddress())).to.equal(await garden1.totalSupply());
      expect(await garden1.totalSupply()).to.equal(ethers.utils.parseEther('0.1').div(await garden1.initialBuyRate()));
    });
  });

  describe('On deposit/ withdrawal', async function () {
    it('supply and positions update accordingly after deposits', async function () {
      const gardenBalance = await weth.balanceOf(garden1.address);
      const supplyBefore = await garden1.totalSupply();
      const wethPositionBefore = await garden1.getPrincipal();
      await garden1.connect(userSigner3).deposit(ethers.utils.parseEther('1'), 1, userSigner3.getAddress(), {
        value: ethers.utils.parseEther('1'),
        gasPrice: 0,
      });
      expect(await garden1.totalContributors()).to.equal(2);
      const wethPosition = await garden1.getPrincipal();
      const gardenBalanceAfter = await weth.balanceOf(garden1.address);
      const supplyAfter = await garden1.totalSupply();
      expect(supplyAfter.div(11)).to.equal(supplyBefore);
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(ethers.utils.parseEther('1'));
      expect(wethPosition.sub(wethPositionBefore)).to.equal(ethers.utils.parseEther('1'));
      expect(await garden1.getPrincipal()).to.equal(ethers.utils.parseEther('1.1'));
      expect(await garden1.getPrincipal()).to.equal(ethers.utils.parseEther('1.1'));
    });

    it('supply and positions update accordingly after deposits & withdraws', async function () {
      await garden1.connect(userSigner3).deposit(ethers.utils.parseEther('1'), 1, userSigner3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      const gardenBalance = await weth.balanceOf(garden1.address);
      const tokenBalance = await garden1.balanceOf(userSigner3.getAddress());
      const supplyBefore = await garden1.totalSupply();
      const wethPositionBefore = await garden1.getPrincipal();
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);
      const protocolTreasury = await weth.balanceOf(treasuryD.address);
      await garden1.connect(userSigner3).withdraw(tokenBalance.div(2), 1, userSigner3.getAddress());
      const wethPosition = await garden1.getPrincipal();
      const gardenBalanceAfter = await weth.balanceOf(garden1.address);
      const supplyAfter = await garden1.totalSupply();
      expect(supplyAfter.add(tokenBalance / 2)).to.equal(supplyBefore);
      expect(gardenBalance.sub(gardenBalanceAfter)).to.equal(ethers.utils.parseEther('0.5'));
      expect(wethPositionBefore.sub(wethPosition)).to.equal(ethers.utils.parseEther('0.5'));
      expect(await garden1.getPrincipal()).to.equal(ethers.utils.parseEther('0.6'));
      // Check that the protocol didn't get an exit fee
      const protocolTreasuryAfter = await weth.balanceOf(treasuryD.address);
      expect(protocolTreasuryAfter.sub(protocolTreasury)).to.equal(ethers.utils.parseEther('0'));
    });
  });
});
