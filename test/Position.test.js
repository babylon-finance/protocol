const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { loadFixture } = waffle;
const { ONE_DAY_IN_SECONDS, NOW } = require('../utils/constants');
const addresses = require('../utils/addresses');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');

describe('Position testing', function () {
  let signer1;
  let signer3;
  let treasury;
  let garden1;
  let garden4;
  let weth;

  beforeEach(async () => {
    ({ signer1, signer3, garden1, garden4, treasury } = await loadFixture(deployFolioFixture));

    weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Initial Positions', async function () {
    it('when creating a garden the variables are at 0', async function () {
      expect(await garden4.totalContributors()).to.equal(0);
      expect(await garden4.principal()).to.equal(ethers.utils.parseEther('0'));
      const wethPosition = await garden4.principal();
      expect(wethPosition).to.equal(ethers.utils.parseEther('0'));
      expect(await garden4.totalSupply()).to.equal(ethers.utils.parseEther('0'));
    });

    it('updates weth balance accordingly when initializing the garden', async function () {
      expect(await garden1.totalContributors()).to.equal(1);
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('0.1'));
      const wethPosition = await garden1.principal();
      expect(await weth.balanceOf(garden1.address)).to.equal(ethers.utils.parseEther('0.1'));
      expect(wethPosition).to.equal(ethers.utils.parseEther('0.1'));
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      expect(await garden1.balanceOf(signer1.getAddress())).to.equal(await garden1.totalSupply());
      expect(await garden1.totalSupply()).to.equal(ethers.utils.parseEther('0.1'));
    });
  });

  describe('On deposit/ withdrawal', async function () {
    it('supply and balances update accordingly after deposits', async function () {
      const gardenBalance = await weth.balanceOf(garden1.address);
      const supplyBefore = await garden1.totalSupply();
      const wethPositionBefore = await garden1.principal();
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
        gasPrice: 0,
      });
      let contributor = await garden1.getContributor(signer3.address);
      expect(contributor[0]).to.equal(contributor[1]);
      expect(contributor[2]).to.equal(0);
      expect(contributor[3]).to.equal(0);

      expect(await garden1.totalContributors()).to.equal(2);
      const wethPosition = await garden1.principal();
      const gardenBalanceAfter = await weth.balanceOf(garden1.address);
      const supplyAfter = await garden1.totalSupply();
      expect(supplyAfter.div(11)).to.equal(supplyBefore);
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(ethers.utils.parseEther('1'));
      expect(wethPosition.sub(wethPositionBefore)).to.equal(ethers.utils.parseEther('1'));
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('1.1'));
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('1.1'));

      await garden1.connect(signer3).deposit(ethers.utils.parseEther('0.5'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('0.5'),
        gasPrice: 0,
      });
      contributor = await garden1.getContributor(signer3.address);
      expect(contributor[0]).to.not.equal(contributor[1]);
      expect(contributor[3]).to.equal(0);
    });

    it('supply and balances update accordingly after deposits & withdraws', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      const gardenBalance = await weth.balanceOf(garden1.address);
      const tokenBalance = await garden1.balanceOf(signer3.getAddress());
      const supplyBefore = await garden1.totalSupply();
      const wethPositionBefore = await garden1.principal();
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);
      const protocolTreasury = await weth.balanceOf(treasury.address);
      await garden1.connect(signer3).withdraw(tokenBalance.div(2), 1, signer3.getAddress());
      const wethPosition = await garden1.principal();
      const gardenBalanceAfter = await weth.balanceOf(garden1.address);
      const supplyAfter = await garden1.totalSupply();
      expect(supplyAfter.add(tokenBalance.div(2))).to.equal(supplyBefore);
      expect(gardenBalance.sub(gardenBalanceAfter)).to.equal(ethers.utils.parseEther('0.5'));
      expect(wethPositionBefore.sub(wethPosition)).to.equal(ethers.utils.parseEther('0.5'));
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('0.6'));
      // Check that the protocol didn't get an exit fee
      const protocolTreasuryAfter = await weth.balanceOf(treasury.address);
      expect(protocolTreasuryAfter.sub(protocolTreasury)).to.equal(ethers.utils.parseEther('0'));
      const contributor = await garden1.getContributor(signer3.address);
      expect(contributor[0]).to.equal(contributor[1]);
      expect(contributor[2]).to.equal(0);
      expect(contributor[3]).to.equal(0);
      // TODO: Check moving average calc
    });
  });
});
