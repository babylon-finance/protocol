const { expect } = require('chai');
const { deployments } = require('hardhat');
const { deploy } = deployments;

const { from, parse, eth } = require('lib/helpers');
const { fund, createWallets } = require('lib/whale');
const { getUsers } = require('lib/web3');
const { getContracts, deployFixture } = require('lib/deploy');
const { increaseTime, increaseBlock, getERC20 } = require('../utils/test-helpers');

const addresses = require('lib/addresses');
const { ONE_DAY_IN_SECONDS, ADDRESS_ZERO } = require('lib/constants');
const { impersonateAddress } = require('../../lib/rpc');
const { ethers } = hre;

describe('migrate', function () {
  let owner;
  let gardens;
  let distributor;
  let ishtarGate;
  let wallets;
  let gnosis;
  let gardenContract;
  let creator;
  let viewerContract;
  let strategies;
  let arkadGarden;
  let creatorWallet;
  let gardenMember;

  async function upgradeRD() {
    const signers = await ethers.getSigners();
    const signer = signers[0];
    const distributorNewImpl = await deploy('RewardsDistributor', {
      from: signer.address,
    });
    const proxyAdmin = await ethers.getContractAt('ProxyAdmin', '0x0C085fd8bbFD78db0107bF17047E8fa906D871DC', gnosis);
    await proxyAdmin.upgrade(distributor.address, distributorNewImpl.address);
  }

  async function upgradeGarden() {
    const signers = await ethers.getSigners();
    const signer = signers[0];
    const gardenBeacon = await ethers.getContractAt(
      'UpgradeableBeacon',
      '0xc8f44C560efe396a6e57e48fF07205bD28AF5E75',
      gnosis,
    );

    const gardenNewImpl = await deploy('Garden', {
      from: signer.address,
      args: [],
      log: true,
    });

    await gardenBeacon.connect(gnosis).upgradeTo(gardenNewImpl.address);
  }

  function normalizeToken(amount) {
    return amount.div(ethers.utils.parseEther('0.001')).toNumber() / 1000;
  }

  describe('after migrating RD into checkpoints', function () {
    beforeEach(async () => {
      ({
        owner,
        gardens,
        distributor,
        ishtarGate,
        gnosis,
        gardenContract,
        creator,
        viewerContract,
        strategies,
        arkadGarden,
        creatorWallet,
        gardenMember,
      } = await deployFixture());

      wallets = await createWallets(1, {
        tokens: [addresses.tokens.DAI, addresses.tokens.ETH],
        amounts: [eth(10000), eth(900)],
      });
      await ishtarGate.connect(owner).setCreatorPermissions(wallets[0].address, true, { gasPrice: 0 });

      arkadGarden = '0xd42B3A30ca89155d6C3499c81F0C4e5A978bE5c2';
      const viewer = '0x3393bf9ff37899735b149fc2f5233b6639903dfa';
      gardenContract = await ethers.getContractAt('Garden', arkadGarden);
      creator = await gardenContract.creator();
      gardenMember = await impersonateAddress('0x166D00d97AF29F7F6a8cD725F601023b843ade66');
      viewerContract = await ethers.getContractAt('BabylonViewer', viewer);
      strategies = await gardenContract.getFinalizedStrategies();
      creatorWallet = await impersonateAddress(creator);
      const reserveContract = await getERC20(addresses.tokens.DAI);
      await fund([creator, wallets[0].address, gardenMember.address], {
        tokens: [addresses.tokens.DAI],
        amounts: [eth(400000)],
      });
      await reserveContract.connect(creatorWallet).approve(arkadGarden, eth(9999999), { gasPrice: 0 });
      await reserveContract.connect(wallets[0]).approve(gardenContract.address, eth(9999999), { gasPrice: 0 });
    });

    it('Unclaimed rewards are equivalent if no new deposit for garden creator (slippage in the future due to old c.power)', async () => {
      const rewards1 = await distributor.getRewards(arkadGarden, await gardenContract.creator(), [...strategies]);
      await upgradeRD();
      console.log('RD upgraded !');
      const rewards2 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      console.log('rewards 1', await normalizeToken(rewards1[4]).toString());
      console.log('rewards 2', await normalizeToken(rewards2[4]).toString());
      console.log('rewards 3', await normalizeToken(rewards3[4]).toString());
      // unclaimed rewards that are always deterministic (strategist/stewards -> both profit and BABL)
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(rewards1[0]); // needs block number after last RD upgrade
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(rewards1[1]);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(rewards1[2]);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(rewards1[3]);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(rewards1[6]);
      // RD upgrade is smooth (no slippage) as c-power is kept for old strategies but it might produce slippage in the future
      expect(rewards2[4]).to.be.closeTo(rewards1[4], rewards1[4].div(100)); // 1%
      expect(rewards2[5]).to.be.closeTo(rewards1[5], rewards1[5].div(100));
      expect(rewards3[4]).to.be.closeTo(rewards2[4], rewards2[4].div(20)); // 5%
      expect(rewards3[5]).to.be.closeTo(rewards2[5], rewards2[5].div(20));
    });
    it('Unclaimed rewards are equivalent if no new deposit of a beta garden member (slippage in the future due to old c.power)', async () => {
      const rewards1 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      await upgradeRD();
      console.log('RD upgraded !');
      const rewards2 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      console.log('rewards 1', rewards1.toString());
      console.log('rewards 2', rewards2.toString());
      console.log('rewards 3', rewards3.toString());
      // unclaimed rewards that are always deterministic (strategist/stewards -> both profit and BABL)
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(rewards1[0]); // needs block number after last RD upgrade
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(rewards1[1]);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(rewards1[2]);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(rewards1[3]);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(rewards1[6]);
      // RD upgrade is smooth (no slippage) as c-power is kept for old strategies but it might produce slippage in the future
      expect(rewards2[4]).to.be.closeTo(rewards1[4], rewards1[4].div(100)); // 1%
      expect(rewards2[5]).to.be.closeTo(rewards1[5], rewards1[5].div(100));
      expect(rewards3[4]).to.be.closeTo(rewards2[4], rewards2[4].div(3)); // 33% higher decreasing slippage
      expect(rewards3[5]).to.be.closeTo(rewards2[5], rewards2[5].div(3));
    });
    it('Unclaimed rewards are equivalent after new deposit of creator (slippage in the future due to old c.power)', async () => {
      const rewards1 = await distributor.getRewards(arkadGarden, await gardenContract.creator(), [...strategies]);
      console.log('---upgrading RD...');
      await upgradeRD();
      console.log('---RD upgraded !');
      console.log('Making a new deposit....');
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), false, { gasPrice: 0 });
      await increaseTime(1);
      const rewards2 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      console.log('rewards 1', await normalizeToken(rewards1[4]).toString());
      console.log('rewards 2', await normalizeToken(rewards2[4]).toString());
      console.log('rewards 3', await normalizeToken(rewards3[4]).toString());
      // unclaimed rewards that are always deterministic (strategist/stewards -> both profit and BABL)
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(rewards1[0]);
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(rewards1[1]);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(rewards1[2]);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(rewards1[3]);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(rewards1[6]);
      // RD upgrade is smooth (no slippage) as c-power is kept for old strategies but it might produce slippage in the future
      expect(rewards2[4]).to.be.closeTo(rewards1[4], rewards1[4].div(100)); // 1%
      expect(rewards2[5]).to.be.closeTo(rewards1[5], rewards1[5].div(100));
      expect(rewards3[4]).to.be.closeTo(rewards2[4], rewards2[4].div(20)); // 5% slippage
      expect(rewards3[5]).to.be.closeTo(rewards2[5], rewards2[5].div(20));
    });
    it('Unclaimed rewards are equivalent after new deposit by beta garden member (slippage in the future due to old c.power)', async () => {
      const rewards1 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      console.log('---upgrading RD...');
      await upgradeRD();
      console.log('---RD upgraded !');
      console.log('Making a new deposit....');
      await gardenContract
        .connect(gardenMember)
        .deposit(eth(2000), eth(1000), gardenMember.address, false, { gasPrice: 0 });
      await increaseTime(1);
      const rewards2 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      console.log('rewards 1', rewards1.toString());
      console.log('rewards 2', rewards2.toString());
      console.log('rewards 3', rewards3.toString());
      // unclaimed rewards that are always deterministic (strategist/stewards -> both profit and BABL)
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(rewards1[0]);
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(rewards1[1]);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(rewards1[2]);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(rewards1[3]);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(rewards1[6]);
      // RD upgrade is smooth (no slippage) as c-power is kept for old strategies but it might produce slippage in the future
      expect(rewards2[4]).to.be.closeTo(rewards1[4], rewards1[4].div(100)); // 1%
      expect(rewards2[5]).to.be.closeTo(rewards1[5], rewards1[5].div(100));
      expect(rewards3[4]).to.be.closeTo(rewards2[4], rewards2[4].div(3)); // 33% slippage
      expect(rewards3[5]).to.be.closeTo(rewards2[5], rewards2[5].div(3));
    });
    it('Unclaimed rewards (old garden strategies) are 0 for new users depositing into a garden', async () => {
      await upgradeRD();
      const rewards1 = await distributor.getRewards(arkadGarden, wallets[0].address, [...strategies]);
      console.log('---RD upgraded !');
      console.log('New user deposit in course...');
      await gardenContract
        .connect(wallets[0])
        .deposit(eth(2000), eth(1000), wallets[0].getAddress(), false, { gasPrice: 0 });
      const rewards2 = await distributor.getRewards(arkadGarden, wallets[0].address, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, wallets[0].address, [...strategies]);
      console.log('rewards 1', rewards1.toString());
      console.log('rewards 2', rewards2.toString());
      console.log('rewards 3', rewards3.toString());
      // unclaimed rewards are 0 and deterministic for non beta users
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(0);
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(0);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(0);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(0);
      expect(rewards3[4]).to.be.eq(rewards2[4]).to.be.eq(0);
      expect(rewards3[5]).to.be.eq(rewards2[5]).to.be.eq(0);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(0);
      expect(rewards3[7]).to.be.eq(rewards2[7]).to.be.eq(0);
    });
    it('Unclaimed rewards are equivalent after multi-big-deposit by garden creator (slippage in the future due to old c.power)', async () => {
      const rewards1 = await distributor.getRewards(arkadGarden, await gardenContract.creator(), [...strategies]);
      console.log('---upgrading RD...');
      await upgradeRD();
      console.log('---RD upgraded !');
      console.log('Making 1st deposit....');
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), false, { gasPrice: 0 });
      await increaseTime(1);
      console.log('Making 2nd deposit....');
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), false, { gasPrice: 0 });
      await increaseTime(1);
      console.log('Making 3rd deposit....');
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(200000), eth(1000), creatorWallet.getAddress(), false, { gasPrice: 0 });
      await increaseTime(1);
      const rewards2 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      console.log('rewards 1', await normalizeToken(rewards1[4]).toString());
      console.log('rewards 2', await normalizeToken(rewards2[4]).toString());
      console.log('rewards 3', await normalizeToken(rewards3[4]).toString());
      // unclaimed rewards that are always deterministic (strategist/stewards -> both profit and BABL)
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(rewards1[0]);
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(rewards1[1]);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(rewards1[2]);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(rewards1[3]);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(rewards1[6]);
      // RD upgrade is smooth (no slippage) as c-power is kept for old strategies but it might produce slippage in the future
      expect(rewards2[4]).to.be.closeTo(rewards1[4], rewards1[4].div(100)); // 1%
      expect(rewards2[5]).to.be.closeTo(rewards1[5], rewards1[5].div(100));
      expect(rewards3[4]).to.be.closeTo(rewards2[4], rewards2[4].div(20)); // 5% slippage
      expect(rewards3[5]).to.be.closeTo(rewards2[5], rewards2[5].div(20));
    });
    it('Unclaimed rewards are equivalent after multi-big-deposit by beta garden member (slippage in the future due to old c.power)', async () => {
      const rewards1 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      console.log('---upgrading RD...');
      await upgradeRD();
      console.log('---RD upgraded !');
      console.log('Making 1st deposit....');
      await gardenContract
        .connect(gardenMember)
        .deposit(eth(2000), eth(1000), gardenMember.address, false, { gasPrice: 0 });
      await increaseTime(1);
      console.log('Making 2nd deposit....');
      await gardenContract
        .connect(gardenMember)
        .deposit(eth(2000), eth(1000), gardenMember.address, false, { gasPrice: 0 });
      await increaseTime(1);
      console.log('Making 3rd deposit....');
      await gardenContract
        .connect(gardenMember)
        .deposit(eth(200000), eth(1000), gardenMember.address, false, { gasPrice: 0 });
      await increaseTime(1);
      const rewards2 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      console.log('rewards 1', rewards1.toString());
      console.log('rewards 2', rewards2.toString());
      console.log('rewards 3', rewards3.toString());
      // unclaimed rewards that are always deterministic (strategist/stewards -> both profit and BABL)
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(rewards1[0]);
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(rewards1[1]);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(rewards1[2]);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(rewards1[3]);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(rewards1[6]);
      // RD upgrade is smooth (no slippage) as c-power is kept for old strategies but it might produce slippage in the future
      expect(rewards2[4]).to.be.closeTo(rewards1[4], rewards1[4].div(100)); // 1%
      expect(rewards2[5]).to.be.closeTo(rewards1[5], rewards1[5].div(100));
      expect(rewards3[4]).to.be.closeTo(rewards2[4], rewards2[4].div(3)); // 33% slippage
      expect(rewards3[5]).to.be.closeTo(rewards2[5], rewards2[5].div(3));
    });
    it('Unclaimed rewards are equivalent after a partial withdrawal by creator (slippage in the future due to old c.power)', async () => {
      console.log('----Getting rewards 1....');
      const rewards1 = await distributor.getRewards(arkadGarden, await gardenContract.creator(), [...strategies]);
      console.log('----Upgrading RD....');
      await upgradeRD();
      await increaseTime(1);
      console.log('----Getting rewards 2....');
      const rewards2 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      console.log('----Partial withdraw in course....');
      // The first checkpoint is created for the user -> we then know prev balance
      await gardenContract
        .connect(creatorWallet)
        .withdraw(eth(500), 1, creatorWallet.getAddress(), false, ADDRESS_ZERO, { gasPrice: 0 });
      await increaseTime(1);
      const rewards3 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      console.log('----Getting rewards 3....');
      const rewards4 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      console.log('rewards 1', rewards1.toString());
      console.log('rewards 2', rewards2.toString());
      console.log('rewards 3', rewards3.toString());
      console.log('rewards 4', rewards4.toString());
      // unclaimed rewards that are always deterministic (strategist/stewards -> both profit and BABL)
      expect(rewards4[0]).to.be.eq(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(rewards1[0]);
      expect(rewards4[1]).to.be.eq(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(rewards1[1]);
      expect(rewards4[2]).to.be.eq(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(rewards1[2]);
      expect(rewards4[3]).to.be.eq(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(rewards1[3]);
      expect(rewards4[6]).to.be.eq(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(rewards1[6]);
      // RD upgrade is smooth (no slippage) as c-power is kept for old strategies but it might produce slippage in the future
      expect(rewards2[4]).to.be.closeTo(rewards1[4], rewards1[4].div(100));
      expect(rewards2[5]).to.be.closeTo(rewards1[5], rewards1[5].div(100));
      expect(rewards3[4]).to.be.closeTo(rewards2[4], rewards2[4].div(100));
      expect(rewards3[5]).to.be.closeTo(rewards2[5], rewards2[5].div(100));
      expect(rewards4[4]).to.be.closeTo(rewards3[4], rewards3[4].div(30));
      expect(rewards4[5]).to.be.closeTo(rewards3[5], rewards3[5].div(30));
    });
    it('Unclaimed rewards can still be claimed after withdrawAll by garden member (slippage limited to previous balance)', async () => {
      const rewards1 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      console.log('---upgrading RD...');
      await upgradeRD();
      await increaseTime(1);
      console.log('---RD upgraded !');
      console.log('Getting rewards 3...');
      const rewards2 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      console.log('WithdrawAll in course....');
      // The first checkpoint is created for the user on withdraw so RD knows its prev balance for calculation
      await gardenContract
        .connect(gardenMember)
        .withdraw(
          await gardenContract.balanceOf(gardenMember.address),
          1,
          gardenMember.getAddress(),
          false,
          ADDRESS_ZERO,
          {
            gasPrice: 0,
          },
        );
      await increaseTime(1);
      console.log('Getting rewards 3...');
      const rewards3 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      console.log('Getting rewards 4...');
      const rewards4 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      await gardenContract.connect(gardenMember).claimReturns([...strategies]); // claim all
      const rewards5 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      console.log('rewards 1', rewards1.toString());
      console.log('rewards 2', rewards2.toString());
      console.log('rewards 3', rewards3.toString());
      console.log('rewards 4', rewards4.toString());
      console.log('rewards 5', rewards5.toString());
      // unclaimed rewards that are always deterministic (strategist/stewards -> both profit and BABL)
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(rewards1[0]);
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(rewards1[1]);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(rewards1[2]);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(rewards1[3]);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(rewards1[6]);
      // RD upgrade is smooth (no slippage) as c-power is kept for old strategies but it might produce slippage in the future
      expect(rewards2[4]).to.be.closeTo(rewards1[4], rewards1[4].div(100)); // 1%
      expect(rewards2[5]).to.be.closeTo(rewards1[5], rewards1[5].div(100)); // 1%
      expect(rewards3[4]).to.be.closeTo(rewards2[4], rewards2[4].div(100)); // 1%
      expect(rewards3[5]).to.be.closeTo(rewards2[5], rewards2[5].div(100)); // 1%
      expect(rewards4[4]).to.be.closeTo(rewards3[4], rewards3[4].div(3)); // 33% slippage after withdrawAll
      expect(rewards4[5]).to.be.closeTo(rewards3[5], rewards3[5].div(3)); // 33% slippage after withdrawAll
      // After claiming, all are set to 0
      expect(rewards5[0]).to.be.eq(0);
      expect(rewards5[1]).to.be.eq(0);
      expect(rewards5[2]).to.be.eq(0);
      expect(rewards5[3]).to.be.eq(0);
      expect(rewards5[4]).to.be.eq(0);
      expect(rewards5[5]).to.be.eq(0);
      expect(rewards5[6]).to.be.eq(0);
      expect(rewards5[7]).to.be.eq(0);
    });
    it('Unclaimed rewards are equivalent if trying to be hacked by withdrawAll and a new big deposit', async () => {
      const rewards1 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      console.log('---upgrading RD...');
      await upgradeRD();
      await increaseTime(1);
      console.log('---RD upgraded !');
      console.log('Getting rewards 3...');
      const rewards2 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      console.log('WithdrawAll in course....');
      // The first checkpoint is created for the user on withdraw so RD knows its prev balance for calculation
      await gardenContract
        .connect(gardenMember)
        .withdraw(
          await gardenContract.balanceOf(gardenMember.address),
          1,
          gardenMember.getAddress(),
          false,
          ADDRESS_ZERO,
          {
            gasPrice: 0,
          },
        );
      await increaseTime(1);
      console.log('');
      console.log('');
      console.log('Getting rewards 3...');
      const rewards3 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      console.log('');
      console.log('');
      console.log('Getting rewards 4...');
      const rewards4 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      await increaseTime(1);
      await gardenContract
        .connect(gardenMember)
        .deposit(eth(10000), eth(1000), gardenMember.getAddress(), false, { gasPrice: 0 });
      await increaseTime(1);
      console.log('');
      console.log('');
      console.log('Getting rewards 5...');
      const rewards5 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      console.log('rewards 1', rewards1.toString());
      console.log('rewards 2', rewards2.toString());
      console.log('rewards 3', rewards3.toString());
      console.log('rewards 4', rewards4.toString());
      console.log('rewards 5', rewards5.toString());
      // unclaimed rewards that are always deterministic (strategist/stewards -> both profit and BABL)
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(rewards1[0]);
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(rewards1[1]);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(rewards1[2]);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(rewards1[3]);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(rewards1[6]);
      // RD upgrade is smooth (no slippage) as c-power is kept for old strategies but it might produce slippage in the future
      expect(rewards2[4]).to.be.closeTo(rewards1[4], rewards1[4].div(100)); // 1%
      expect(rewards2[5]).to.be.closeTo(rewards1[5], rewards1[5].div(100)); // 1%
      expect(rewards3[4]).to.be.closeTo(rewards2[4], rewards2[4].div(100)); // 1%
      expect(rewards3[5]).to.be.closeTo(rewards2[5], rewards2[5].div(100)); // 1%
      expect(rewards4[4]).to.be.closeTo(rewards3[4], rewards3[4].div(3)); // 33% slippage after withdrawAll
      expect(rewards4[5]).to.be.closeTo(rewards3[5], rewards3[5].div(3)); // 33% slippage after withdrawAll
      // After new deposit it is still equivalent
      expect(rewards5[4]).to.be.closeTo(rewards4[4], rewards4[4].div(100)); // 1%
      expect(rewards5[5]).to.be.closeTo(rewards4[5], rewards4[5].div(100)); // 1%
    });
    it('Pending rewards are equivalent if no new deposit of garden creator', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await upgradeRD();
      await increaseTime(1);
      console.log('RD upgraded !');
      console.log('Estimating rewards 2...');
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      console.log('Increasing time...');
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      console.log('Estimating rewards 3...');
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      console.log('estimateRewards 1', estimateRewards1.toString());
      console.log('estimateRewards 2', estimateRewards2.toString());
      console.log('estimateRewards 3', estimateRewards3.toString());
      // mining is delivering more BABL along the time
      // new blocks has less profit in this example (strategies are getting less NAV)
      expect(estimateRewards3[0]).to.be.gt(estimateRewards2[0]).to.be.gt(estimateRewards1[0]);
      expect(estimateRewards3[1]).to.be.lt(estimateRewards2[1]).to.be.lt(estimateRewards1[1]);
      expect(estimateRewards3[2]).to.be.gt(estimateRewards2[2]).to.be.gt(estimateRewards1[2]);
      expect(estimateRewards3[3]).to.be.lt(estimateRewards2[3]).to.be.lt(estimateRewards1[3]);
      expect(estimateRewards3[4]).to.be.gt(estimateRewards2[4]).to.be.gt(estimateRewards1[4]);
      expect(estimateRewards3[5]).to.be.gt(estimateRewards2[5]).to.be.gt(estimateRewards1[5]);
      expect(estimateRewards3[6]).to.be.lt(estimateRewards2[6]).to.be.lt(estimateRewards1[6]);
      expect(estimateRewards3[7]).to.be.gt(estimateRewards2[7]).to.be.gt(estimateRewards1[7]);
      expect(estimateRewards2[0]).to.be.closeTo(estimateRewards1[0], estimateRewards1[0].div(100)); // 1%
      expect(estimateRewards2[1]).to.be.closeTo(estimateRewards1[1], estimateRewards1[1].div(100));
      expect(estimateRewards2[2]).to.be.closeTo(estimateRewards1[2], estimateRewards1[2].div(100));
      expect(estimateRewards2[3]).to.be.closeTo(estimateRewards1[3], estimateRewards1[3].div(100));
      expect(estimateRewards2[4]).to.be.closeTo(estimateRewards1[4], estimateRewards1[4].div(100));
      expect(estimateRewards2[5]).to.be.closeTo(estimateRewards1[5], estimateRewards1[5].div(100));
      expect(estimateRewards2[6]).to.be.closeTo(estimateRewards1[6], estimateRewards1[6].div(100));
      expect(estimateRewards2[7]).to.be.closeTo(estimateRewards1[7], estimateRewards1[7].div(100));
    });
    it('Pending rewards are equivalent if no new deposit of garden member', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, gardenMember.address);
      await upgradeRD();
      await increaseTime(1);
      console.log('RD upgraded !');
      console.log('Estimating rewards 2...');
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, gardenMember.address);
      console.log('Increasing time...');
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      console.log('Estimating rewards 3...');
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, gardenMember.address);
      console.log('estimateRewards 1', estimateRewards1.toString());
      console.log('estimateRewards 2', estimateRewards2.toString());
      console.log('estimateRewards 3', estimateRewards3.toString());
      // mining is delivering more BABL along the time
      // new blocks has less profit in this example (strategies are getting less NAV)
      expect(estimateRewards3[0]).to.be.eq(estimateRewards2[0]).to.be.eq(estimateRewards1[0]).to.be.eq(0);
      expect(estimateRewards3[1]).to.be.eq(estimateRewards2[1]).to.be.eq(estimateRewards1[1]).to.be.eq(0);
      expect(estimateRewards3[2]).to.be.gt(estimateRewards2[2]).to.be.gt(estimateRewards1[2]);
      expect(estimateRewards3[3]).to.be.lt(estimateRewards2[3]).to.be.lt(estimateRewards1[3]);
      expect(estimateRewards3[4]).to.be.gt(estimateRewards2[4]).to.be.gt(estimateRewards1[4]);
      expect(estimateRewards3[5]).to.be.gt(estimateRewards2[5]).to.be.gt(estimateRewards1[5]);
      expect(estimateRewards3[6]).to.be.lt(estimateRewards2[6]).to.be.lt(estimateRewards1[6]);
      expect(estimateRewards3[7]).to.be.eq(estimateRewards2[7]).to.be.eq(estimateRewards1[7]).to.be.eq(0);
      expect(estimateRewards2[0]).to.be.closeTo(estimateRewards1[0], estimateRewards1[0].div(100)); // 1%
      expect(estimateRewards2[1]).to.be.closeTo(estimateRewards1[1], estimateRewards1[1].div(100));
      expect(estimateRewards2[2]).to.be.closeTo(estimateRewards1[2], estimateRewards1[2].div(100));
      expect(estimateRewards2[3]).to.be.closeTo(estimateRewards1[3], estimateRewards1[3].div(100));
      expect(estimateRewards2[4]).to.be.closeTo(estimateRewards1[4], estimateRewards1[4].div(100));
      expect(estimateRewards2[5]).to.be.closeTo(estimateRewards1[5], estimateRewards1[5].div(100));
      expect(estimateRewards2[6]).to.be.closeTo(estimateRewards1[6], estimateRewards1[6].div(100));
      expect(estimateRewards2[7]).to.be.closeTo(estimateRewards1[7], estimateRewards1[7].div(100));
    });
    it('Pending rewards are zero if a new user has not joined yet', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      await upgradeRD();
      await increaseTime(1);
      console.log('RD upgraded !');
      console.log('Estimating rewards 2...');
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      console.log('Increasing time...');
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      console.log('Estimating rewards 3...');
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      console.log('estimateRewards 1', estimateRewards1.toString());
      console.log('estimateRewards 2', estimateRewards2.toString());
      console.log('estimateRewards 3', estimateRewards3.toString());
      // mining is delivering more BABL along the time
      // new blocks has less profit in this example (strategies are getting less NAV)
      expect(estimateRewards3[0]).to.be.eq(estimateRewards2[0]).to.be.eq(estimateRewards1[0]).to.be.eq(0);
      expect(estimateRewards3[1]).to.be.eq(estimateRewards2[1]).to.be.eq(estimateRewards1[1]).to.be.eq(0);
      expect(estimateRewards3[2]).to.be.eq(estimateRewards2[2]).to.be.eq(estimateRewards1[2]).to.be.eq(0);
      expect(estimateRewards3[3]).to.be.eq(estimateRewards2[3]).to.be.eq(estimateRewards1[3]).to.be.eq(0);
      expect(estimateRewards3[4]).to.be.eq(estimateRewards2[4]).to.be.eq(estimateRewards1[4]).to.be.eq(0);
      expect(estimateRewards3[5]).to.be.eq(estimateRewards2[5]).to.be.eq(estimateRewards1[5]).to.be.eq(0);
      expect(estimateRewards3[6]).to.be.eq(estimateRewards2[6]).to.be.eq(estimateRewards1[6]).to.be.eq(0);
      expect(estimateRewards3[7]).to.be.eq(estimateRewards2[7]).to.be.eq(estimateRewards1[7]).to.be.eq(0);
    });
    it('Pending rewards are deterministic and implement firewall-ing for new deposit giving only proportional (1 new deposit by creator)', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await upgradeRD();
      console.log('RD upgraded !');
      console.log('Estimating rewards 2...');
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await increaseTime(1);
      console.log('New deposit in course....');
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), false, { gasPrice: 0 });
      console.log('Estimating rewards 3...');
      await increaseTime(1);
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      console.log('Increasing time...');
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      console.log('Estimating rewards 4...');
      const [, , estimateRewards4] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      console.log('estimateRewards 1', estimateRewards1.toString());
      console.log('estimateRewards 2', estimateRewards2.toString());
      console.log('estimateRewards 3', estimateRewards3.toString());
      console.log('estimateRewards 4', estimateRewards4.toString());

      // Before and after upgrade
      expect(estimateRewards2[0]).to.be.closeTo(estimateRewards1[0], estimateRewards1[0].div(100)); // 1%
      expect(estimateRewards2[1]).to.be.closeTo(estimateRewards1[1], estimateRewards1[1].div(100));
      expect(estimateRewards2[2]).to.be.closeTo(estimateRewards1[2], estimateRewards1[2].div(100));
      expect(estimateRewards2[3]).to.be.closeTo(estimateRewards1[3], estimateRewards1[3].div(100));
      expect(estimateRewards2[4]).to.be.closeTo(estimateRewards1[4], estimateRewards1[4].div(100));
      expect(estimateRewards2[5]).to.be.closeTo(estimateRewards1[5], estimateRewards1[5].div(100));
      expect(estimateRewards2[6]).to.be.closeTo(estimateRewards1[6], estimateRewards1[6].div(100));
      expect(estimateRewards2[7]).to.be.closeTo(estimateRewards1[7], estimateRewards1[7].div(100));
      // Before and after new checkpoint
      expect(estimateRewards3[0]).to.be.closeTo(estimateRewards2[0], estimateRewards2[0].div(100)); // 1%
      expect(estimateRewards3[1]).to.be.closeTo(estimateRewards2[1], estimateRewards2[1].div(100));
      expect(estimateRewards3[2]).to.be.closeTo(estimateRewards2[2], estimateRewards2[2].div(100));
      expect(estimateRewards3[3]).to.be.closeTo(estimateRewards2[3], estimateRewards2[3].div(100));
      expect(estimateRewards3[4]).to.be.closeTo(estimateRewards2[4], estimateRewards2[4].div(13)); // 7%
      expect(estimateRewards3[5]).to.be.closeTo(estimateRewards2[5], estimateRewards2[5].div(13)); // 7%
      expect(estimateRewards3[6]).to.be.closeTo(estimateRewards2[6], estimateRewards2[6].div(100));
      expect(estimateRewards3[7]).to.be.closeTo(estimateRewards2[7], estimateRewards2[7].div(22)); // 4%

      // Deposit replaces c-power by checkpoints so historic time impact is no longer valid so there is a slightly reduction despite a deposit
      expect(estimateRewards3[4]).to.be.lt(estimateRewards2[4]);

      // mining is delivering more BABL along the time
      // new blocks has less profit in this example
      expect(estimateRewards4[0])
        .to.be.gt(estimateRewards3[0])
        .to.be.gt(estimateRewards2[0])
        .to.be.gt(estimateRewards1[0]);
      expect(estimateRewards4[1])
        .to.be.lt(estimateRewards3[1])
        .to.be.lt(estimateRewards2[1])
        .to.be.lt(estimateRewards1[1]);
      expect(estimateRewards4[2])
        .to.be.gt(estimateRewards3[2])
        .to.be.gt(estimateRewards2[2])
        .to.be.gt(estimateRewards1[2]);
      expect(estimateRewards4[3])
        .to.be.lt(estimateRewards3[3])
        .to.be.lt(estimateRewards2[3])
        .to.be.lt(estimateRewards1[3]);
      expect(estimateRewards4[4])
        .to.be.gt(estimateRewards3[4])
        .to.be.gt(estimateRewards2[4])
        .to.be.gt(estimateRewards1[4]);
      expect(estimateRewards4[5])
        .to.be.gt(estimateRewards3[5])
        .to.be.gt(estimateRewards2[5])
        .to.be.gt(estimateRewards1[5]);
      expect(estimateRewards4[6])
        .to.be.lt(estimateRewards3[6])
        .to.be.lt(estimateRewards2[6])
        .to.be.lt(estimateRewards1[6]);
      expect(estimateRewards4[7])
        .to.be.gt(estimateRewards3[7])
        .to.be.gt(estimateRewards3[7])
        .to.be.gt(estimateRewards2[7])
        .to.be.gt(estimateRewards1[7]);
    });
    it('Pending rewards are equivalent for a beta user after a new big deposit of a new joining member', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await upgradeRD();
      console.log('RD upgraded !');
      console.log('Estimating rewards 2...');
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await increaseTime(1);
      console.log('New deposit in course....');
      await gardenContract
        .connect(wallets[0])
        .deposit(eth(200000), eth(1000), wallets[0].getAddress(), false, { gasPrice: 0 });
      console.log('Estimating rewards 3...');
      await increaseTime(1);
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      console.log('Increasing time...');
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      console.log('Estimating rewards 4...');
      const [, , estimateRewards4] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      console.log('estimateRewards 1', estimateRewards1.toString());
      console.log('estimateRewards 2', estimateRewards2.toString());
      console.log('estimateRewards 3', estimateRewards3.toString());
      console.log('estimateRewards 4', estimateRewards4.toString());

      // Before and after upgrade
      expect(estimateRewards2[0]).to.be.closeTo(estimateRewards1[0], estimateRewards1[0].div(100)); // 1%
      expect(estimateRewards2[1]).to.be.closeTo(estimateRewards1[1], estimateRewards1[1].div(100));
      expect(estimateRewards2[2]).to.be.closeTo(estimateRewards1[2], estimateRewards1[2].div(100));
      expect(estimateRewards2[3]).to.be.closeTo(estimateRewards1[3], estimateRewards1[3].div(100));
      expect(estimateRewards2[4]).to.be.closeTo(estimateRewards1[4], estimateRewards1[4].div(100));
      expect(estimateRewards2[5]).to.be.closeTo(estimateRewards1[5], estimateRewards1[5].div(100));
      expect(estimateRewards2[6]).to.be.closeTo(estimateRewards1[6], estimateRewards1[6].div(100));
      expect(estimateRewards2[7]).to.be.closeTo(estimateRewards1[7], estimateRewards1[7].div(100));
      // Before and after new checkpoint
      expect(estimateRewards3[0]).to.be.closeTo(estimateRewards2[0], estimateRewards2[0].div(100)); // 1%
      expect(estimateRewards3[1]).to.be.closeTo(estimateRewards2[1], estimateRewards2[1].div(100));
      expect(estimateRewards3[2]).to.be.closeTo(estimateRewards2[2], estimateRewards2[2].div(100));
      expect(estimateRewards3[3]).to.be.closeTo(estimateRewards2[3], estimateRewards2[3].div(100));
      expect(estimateRewards3[4]).to.be.closeTo(estimateRewards2[4], estimateRewards2[4].div(100));
      expect(estimateRewards3[5]).to.be.closeTo(estimateRewards2[5], estimateRewards2[5].div(100));
      expect(estimateRewards3[6]).to.be.closeTo(estimateRewards2[6], estimateRewards2[6].div(100));
      expect(estimateRewards3[7]).to.be.closeTo(estimateRewards2[7], estimateRewards2[7].div(100));

      // the new big deposit by a different user is affecting a bit to current user
      expect(estimateRewards3[4]).to.be.lt(estimateRewards2[4]);

      // mining is delivering more BABL along the time
      // new blocks has less profit in this example
      expect(estimateRewards4[0])
        .to.be.gt(estimateRewards3[0])
        .to.be.gt(estimateRewards2[0])
        .to.be.gt(estimateRewards1[0]);
      expect(estimateRewards4[1])
        .to.be.lt(estimateRewards3[1])
        .to.be.lt(estimateRewards2[1])
        .to.be.lt(estimateRewards1[1]);
      expect(estimateRewards4[2])
        .to.be.gt(estimateRewards3[2])
        .to.be.gt(estimateRewards2[2])
        .to.be.gt(estimateRewards1[2]);
      expect(estimateRewards4[3])
        .to.be.lt(estimateRewards3[3])
        .to.be.lt(estimateRewards2[3])
        .to.be.lt(estimateRewards1[3]);
      expect(estimateRewards4[4])
        .to.be.gt(estimateRewards3[4])
        .to.be.gt(estimateRewards2[4])
        .to.be.gt(estimateRewards1[4]);
      expect(estimateRewards4[5])
        .to.be.gt(estimateRewards3[5])
        .to.be.gt(estimateRewards2[5])
        .to.be.gt(estimateRewards1[5]);
      expect(estimateRewards4[6])
        .to.be.lt(estimateRewards3[6])
        .to.be.lt(estimateRewards2[6])
        .to.be.lt(estimateRewards1[6]);
      expect(estimateRewards4[7])
        .to.be.gt(estimateRewards3[7])
        .to.be.gt(estimateRewards3[7])
        .to.be.gt(estimateRewards2[7])
        .to.be.gt(estimateRewards1[7]);
    });
    it('Pending rewards are equivalent for 2 beta users after a new deposit from them + a big deposit of a new joining member', async () => {
      console.log('Estimating rewards 1...');
      const [, , estimateRewards1Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards1GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards1NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      await upgradeRD();
      console.log('RD upgraded !');
      console.log('Estimating rewards 2...');
      const [, , estimateRewards2Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards2GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards2NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      await increaseTime(1);
      console.log('New creator deposit in course....');
      await gardenContract.connect(creatorWallet).deposit(eth(2000), eth(1000), creator, false, { gasPrice: 0 });
      await increaseTime(1);
      console.log('Estimating rewards 3...');
      const [, , estimateRewards3Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards3GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards3NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      console.log('New beta user deposit in course....');
      await gardenContract
        .connect(gardenMember)
        .deposit(eth(2000), eth(1000), gardenMember.address, false, { gasPrice: 0 });
      console.log('Estimating rewards 4...');
      const [, , estimateRewards4Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards4GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards4NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      console.log('New member BIG deposit in course....');
      await gardenContract
        .connect(wallets[0])
        .deposit(eth(200000), eth(1000), wallets[0].getAddress(), false, { gasPrice: 0 });
      console.log('Estimating rewards 5...');
      await increaseTime(1);
      const [, , estimateRewards5Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards5GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards5NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      console.log('Increasing time...');
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      console.log('Estimating rewards 6...');
      const [, , estimateRewards6Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards6GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards6NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      console.log('estimateRewards 1 Creator', estimateRewards1Creator.toString());
      console.log('estimateRewards 2 Creator', estimateRewards2Creator.toString());
      console.log('estimateRewards 3 Creator', estimateRewards3Creator.toString());
      console.log('estimateRewards 4 Creator', estimateRewards4Creator.toString());
      console.log('estimateRewards 5 Creator', estimateRewards5Creator.toString());
      console.log('estimateRewards 6 Creator', estimateRewards6Creator.toString());

      console.log('estimateRewards 1 Garden Member', estimateRewards1GardenMember.toString());
      console.log('estimateRewards 2 Garden Member', estimateRewards2GardenMember.toString());
      console.log('estimateRewards 3 Garden Member', estimateRewards3GardenMember.toString());
      console.log('estimateRewards 4 Garden Member', estimateRewards4GardenMember.toString());
      console.log('estimateRewards 5 Garden Member', estimateRewards5GardenMember.toString());
      console.log('estimateRewards 6 Garden Member', estimateRewards6GardenMember.toString());

      console.log('estimateRewards 1 New User', estimateRewards1NewUser.toString());
      console.log('estimateRewards 2 New User', estimateRewards2NewUser.toString());
      console.log('estimateRewards 3 New User', estimateRewards3NewUser.toString());
      console.log('estimateRewards 4 New User', estimateRewards4NewUser.toString());
      console.log('estimateRewards 5 New User', estimateRewards5NewUser.toString());
      console.log('estimateRewards 6 New User', estimateRewards6NewUser.toString());
    });
    it.only('Pending rewards are equivalent for 2 beta users after a new deposit from them + a big deposit of a new joining member', async () => {
      console.log('New user depositing using old garden and RD');
      await gardenContract
        .connect(wallets[0])
        .deposit(eth(200000), eth(1000), wallets[0].getAddress(), false, { gasPrice: 0 });
      await increaseTime(1);
      console.log('Estimating rewards 1...');
      const [, , estimateRewards1Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards1GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards1NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      await upgradeGarden(); // upgrading garden
      await upgradeRD(); // upgrading RD
      console.log('RD upgraded !');
      console.log('Estimating rewards 2...');
      const [, , estimateRewards2Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards2GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards2NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      await increaseTime(1);
      console.log('New creator deposit in course....');
      await gardenContract.connect(creatorWallet).deposit(eth(2000), eth(1000), creator, false, { gasPrice: 0 });
      await increaseTime(1);
      console.log('Estimating rewards 3...');
      const [, , estimateRewards3Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards3GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards3NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      console.log('New beta user deposit in course....');
      await gardenContract
        .connect(gardenMember)
        .deposit(eth(2000), eth(1000), gardenMember.address, false, { gasPrice: 0 });
      console.log('Estimating rewards 4...');
      const [, , estimateRewards4Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards4GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards4NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      console.log('New member BIG deposit in course....');
      await gardenContract
        .connect(wallets[0])
        .deposit(eth(200000), eth(1000), wallets[0].getAddress(), false, { gasPrice: 0 });
      console.log('Estimating rewards 5...');
      await increaseTime(1);
      const [, , estimateRewards5Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards5GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards5NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      console.log('Increasing time...');
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      console.log('Estimating rewards 6...');
      const [, , estimateRewards6Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards6GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards6NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      console.log('estimateRewards 1 Creator', estimateRewards1Creator.toString());
      console.log('estimateRewards 2 Creator', estimateRewards2Creator.toString());
      console.log('estimateRewards 3 Creator', estimateRewards3Creator.toString());
      console.log('estimateRewards 4 Creator', estimateRewards4Creator.toString());
      console.log('estimateRewards 5 Creator', estimateRewards5Creator.toString());
      console.log('estimateRewards 6 Creator', estimateRewards6Creator.toString());

      console.log('estimateRewards 1 Garden Member', estimateRewards1GardenMember.toString());
      console.log('estimateRewards 2 Garden Member', estimateRewards2GardenMember.toString());
      console.log('estimateRewards 3 Garden Member', estimateRewards3GardenMember.toString());
      console.log('estimateRewards 4 Garden Member', estimateRewards4GardenMember.toString());
      console.log('estimateRewards 5 Garden Member', estimateRewards5GardenMember.toString());
      console.log('estimateRewards 6 Garden Member', estimateRewards6GardenMember.toString());

      console.log('estimateRewards 1 New User', estimateRewards1NewUser.toString());
      console.log('estimateRewards 2 New User', estimateRewards2NewUser.toString());
      console.log('estimateRewards 3 New User', estimateRewards3NewUser.toString());
      console.log('estimateRewards 4 New User', estimateRewards4NewUser.toString());
      console.log('estimateRewards 5 New User', estimateRewards5NewUser.toString());
      console.log('estimateRewards 6 New User', estimateRewards6NewUser.toString());
    });
    it('Pending rewards are deterministic and implement firewall-ing for new deposit giving only proportional (multideposit by creator)', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await upgradeRD();
      console.log('RD upgraded !');
      console.log('Estimating rewards 2...');
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      console.log('1st new deposit in course....');
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), false, { gasPrice: 0 });
      await increaseTime(10);
      console.log('2nd new deposit in course....');
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), false, { gasPrice: 0 });
      await increaseTime(10);
      console.log('3rd new deposit in course....');
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), false, { gasPrice: 0 });
      console.log('Estimating rewards 3...');
      await increaseTime(1);
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      console.log('Increasing time...');
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      console.log('Estimating rewards 4...');
      const [, , estimateRewards4] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      console.log('estimateRewards 1', estimateRewards1.toString());
      console.log('estimateRewards 2', estimateRewards2.toString());
      console.log('estimateRewards 3', estimateRewards3.toString());
      console.log('estimateRewards 4', estimateRewards4.toString());

      // Before and after upgrade
      expect(estimateRewards2[0]).to.be.closeTo(estimateRewards1[0], estimateRewards1[0].div(100)); // 1%
      expect(estimateRewards2[1]).to.be.closeTo(estimateRewards1[1], estimateRewards1[1].div(100));
      expect(estimateRewards2[2]).to.be.closeTo(estimateRewards1[2], estimateRewards1[2].div(100));
      expect(estimateRewards2[3]).to.be.closeTo(estimateRewards1[3], estimateRewards1[3].div(100));
      expect(estimateRewards2[4]).to.be.closeTo(estimateRewards1[4], estimateRewards1[4].div(100));
      expect(estimateRewards2[5]).to.be.closeTo(estimateRewards1[5], estimateRewards1[5].div(100));
      expect(estimateRewards2[6]).to.be.closeTo(estimateRewards1[6], estimateRewards1[6].div(100));
      expect(estimateRewards2[7]).to.be.closeTo(estimateRewards1[7], estimateRewards1[7].div(100));
      // Before and after new checkpoint
      expect(estimateRewards3[0]).to.be.closeTo(estimateRewards2[0], estimateRewards2[0].div(100)); // 1%
      expect(estimateRewards3[1]).to.be.closeTo(estimateRewards2[1], estimateRewards2[1].div(100));
      expect(estimateRewards3[2]).to.be.closeTo(estimateRewards2[2], estimateRewards2[2].div(100));
      expect(estimateRewards3[3]).to.be.closeTo(estimateRewards2[3], estimateRewards2[3].div(100));
      expect(estimateRewards3[4]).to.be.closeTo(estimateRewards2[4], estimateRewards2[4].div(13)); // 7%
      expect(estimateRewards3[5]).to.be.closeTo(estimateRewards2[5], estimateRewards2[5].div(13)); // 7%
      expect(estimateRewards3[6]).to.be.closeTo(estimateRewards2[6], estimateRewards2[6].div(100));
      expect(estimateRewards3[7]).to.be.closeTo(estimateRewards2[7], estimateRewards2[7].div(22)); // 4%

      // mining is delivering more BABL along the time
      // new blocks has less profit in this example
      expect(estimateRewards4[0])
        .to.be.gt(estimateRewards3[0])
        .to.be.gt(estimateRewards2[0])
        .to.be.gt(estimateRewards1[0]);
      expect(estimateRewards4[1])
        .to.be.lt(estimateRewards3[1])
        .to.be.lt(estimateRewards2[1])
        .to.be.lt(estimateRewards1[1]);
      expect(estimateRewards4[2])
        .to.be.gt(estimateRewards3[2])
        .to.be.gt(estimateRewards2[2])
        .to.be.gt(estimateRewards1[2]);
      expect(estimateRewards4[3])
        .to.be.lt(estimateRewards3[3])
        .to.be.lt(estimateRewards2[3])
        .to.be.lt(estimateRewards1[3]);
      expect(estimateRewards4[4])
        .to.be.gt(estimateRewards3[4])
        .to.be.gt(estimateRewards2[4])
        .to.be.gt(estimateRewards1[4]);
      expect(estimateRewards4[5])
        .to.be.gt(estimateRewards3[5])
        .to.be.gt(estimateRewards2[5])
        .to.be.gt(estimateRewards1[5]);
      expect(estimateRewards4[6])
        .to.be.lt(estimateRewards3[6])
        .to.be.lt(estimateRewards2[6])
        .to.be.lt(estimateRewards1[6]);
      expect(estimateRewards4[7])
        .to.be.gt(estimateRewards3[7])
        .to.be.gt(estimateRewards3[7])
        .to.be.gt(estimateRewards2[7])
        .to.be.gt(estimateRewards1[7]);
    });
    it('Pending rewards are deterministic != 0 for a new user and implement firewall-ing giving only proportional vs. strategy start time', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      await upgradeRD();

      console.log('RD upgraded !');
      console.log('New deposit in course....');
      await gardenContract
        .connect(wallets[0])
        .deposit(eth(2000), eth(1000), wallets[0].getAddress(), false, { gasPrice: 0 });
      console.log('Estimating rewards 2...');
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      console.log('Increasing time...');
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      console.log('Estimating rewards 3...');
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      console.log('estimateRewards 1', estimateRewards1.toString());
      console.log('estimateRewards 2', estimateRewards2.toString());
      console.log('estimateRewards 3', estimateRewards3.toString());
      // mining is delivering more BABL along the time
      // new blocks has less profit in this example
      expect(estimateRewards3[0]).to.be.eq(estimateRewards2[0]).to.be.eq(estimateRewards1[0]).to.be.eq(0);
      expect(estimateRewards3[1]).to.be.eq(estimateRewards2[1]).to.be.eq(estimateRewards1[1]).to.be.eq(0);
      expect(estimateRewards3[2]).to.be.eq(estimateRewards2[2]).to.be.eq(estimateRewards1[2]).to.be.eq(0);
      expect(estimateRewards3[3]).to.be.eq(estimateRewards2[3]).to.be.eq(estimateRewards1[3]).to.be.eq(0);
      expect(estimateRewards3[4]).to.be.gt(estimateRewards2[4]).to.be.gt(estimateRewards1[4]); // after upgrade we pass from c-power to deterministic so it decreases a bit
      expect(estimateRewards3[5]).to.be.gt(estimateRewards2[5]).to.be.gt(estimateRewards1[5]); // after upgrade we pass from c-power to deterministic so it decreases a bit
      expect(estimateRewards3[6]).to.be.eq(estimateRewards2[6]).to.be.eq(estimateRewards1[6]).to.be.eq(0);
      expect(estimateRewards3[7]).to.be.eq(estimateRewards2[7]).to.be.eq(estimateRewards1[7]).to.be.eq(0); // after upgrade we pass from c-power to deterministic so it decreases a bit
      expect(estimateRewards2[4]).to.be.eq(estimateRewards1[4]).to.be.eq(0);
      expect(estimateRewards2[5]).to.be.eq(estimateRewards1[5]).to.be.eq(0);
    });
    it('Pending rewards follow the deterministic path after a partial withdrawal', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await upgradeRD();
      await increaseTime(1);
      console.log('RD upgraded !');
      console.log('Partial withdrawing in course....');
      // The first checkpoint is created for the user -> we then know prev balance
      await gardenContract
        .connect(creatorWallet)
        .withdraw(eth(10000), 1, creatorWallet.getAddress(), false, ADDRESS_ZERO, { gasPrice: 0 });
      await increaseTime(1);
      console.log('Estimating rewards 2...');
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      console.log('Increasing time...');
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      console.log('Estimating rewards 3...');
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      console.log('estimateRewards 1', estimateRewards1.toString());
      console.log('estimateRewards 2', estimateRewards2.toString());
      console.log('estimateRewards 3', estimateRewards3.toString());
      // mining is delivering more BABL along the time
      // new blocks has less profit in this example
      expect(estimateRewards3[0]).to.be.gt(estimateRewards2[0]).to.be.gt(estimateRewards1[0]);
      expect(estimateRewards3[1]).to.be.lt(estimateRewards2[1]).to.be.lt(estimateRewards1[1]);
      expect(estimateRewards3[2]).to.be.gt(estimateRewards2[2]).to.be.gt(estimateRewards1[2]);
      expect(estimateRewards3[3]).to.be.lt(estimateRewards2[3]).to.be.lt(estimateRewards1[3]);
      expect(estimateRewards3[4]).to.be.gt(estimateRewards2[4]).to.be.gt(estimateRewards1[4]);
      expect(estimateRewards3[5]).to.be.gt(estimateRewards2[5]).to.be.gt(estimateRewards1[5]);
      expect(estimateRewards3[6]).to.be.lt(estimateRewards2[6]).to.be.lt(estimateRewards1[6]);
      expect(estimateRewards3[7]).to.be.gt(estimateRewards2[7]).to.be.gt(estimateRewards1[7]);
      expect(estimateRewards2[0]).to.be.closeTo(estimateRewards1[0], estimateRewards1[0].div(100)); // 1%
      expect(estimateRewards2[1]).to.be.closeTo(estimateRewards1[1], estimateRewards1[1].div(100));
      expect(estimateRewards2[2]).to.be.closeTo(estimateRewards1[2], estimateRewards1[2].div(100));
      expect(estimateRewards2[3]).to.be.closeTo(estimateRewards1[3], estimateRewards1[3].div(100));
      expect(estimateRewards2[4]).to.be.closeTo(estimateRewards1[4], estimateRewards1[4].div(100));
      expect(estimateRewards2[5]).to.be.closeTo(estimateRewards1[5], estimateRewards1[5].div(100));
      expect(estimateRewards2[6]).to.be.closeTo(estimateRewards1[6], estimateRewards1[6].div(100));
      expect(estimateRewards2[7]).to.be.closeTo(estimateRewards1[7], estimateRewards1[7].div(100));
    });
    it('LP Pending rewards become zero after withdrawalAll (steward rewards continue increasing...)', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, gardenMember.address);
      await upgradeRD();

      console.log('RD upgraded !');
      console.log('Estimating rewards 2...');
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, gardenMember.address);
      console.log('WithdrawAll in course....');
      // The first checkpoint is created for the user -> we then know prev balance
      await gardenContract
        .connect(gardenMember)
        .withdraw(
          await gardenContract.balanceOf(gardenMember.address),
          1,
          gardenMember.getAddress(),
          false,
          ADDRESS_ZERO,
          {
            gasPrice: 0,
          },
        );
      console.log('Increasing time...');
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      console.log('Estimating rewards 3...');
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, gardenMember.address);
      console.log('estimateRewards 1', estimateRewards1.toString());
      console.log('estimateRewards 2', estimateRewards2.toString());
      console.log('estimateRewards 3', estimateRewards3.toString());
      // mining is delivering more BABL along the time
      // new blocks has less profit in this example
      expect(estimateRewards3[0]).to.be.eq(estimateRewards2[0]).to.be.eq(estimateRewards1[0]).to.be.eq(0);
      expect(estimateRewards3[1]).to.be.eq(estimateRewards2[1]).to.be.eq(estimateRewards1[1]).to.be.eq(0);
      expect(estimateRewards3[2]).to.be.gt(estimateRewards2[2]).to.be.gt(estimateRewards1[2]);
      expect(estimateRewards3[3]).to.be.lt(estimateRewards2[3]).to.be.lt(estimateRewards1[3]);
      expect(estimateRewards3[4]).to.be.eq(0); // LP BABL is zero after withdrawAll
      expect(estimateRewards3[5]).to.be.lt(estimateRewards2[5]).to.be.lt(estimateRewards1[5]); // after withdrawAll LP is zero but strategist && stewards are kept
      expect(estimateRewards3[6]).to.be.lt(estimateRewards2[6]).to.be.lt(estimateRewards1[6]);
      expect(estimateRewards3[7]).to.be.eq(estimateRewards2[7]).to.be.eq(estimateRewards1[7]).to.be.eq(0);
      expect(estimateRewards2[0]).to.be.closeTo(estimateRewards1[0], estimateRewards1[0].div(100)); // 1%
      expect(estimateRewards2[1]).to.be.closeTo(estimateRewards1[1], estimateRewards1[1].div(100));
      expect(estimateRewards2[2]).to.be.closeTo(estimateRewards1[2], estimateRewards1[2].div(100));
      expect(estimateRewards2[3]).to.be.closeTo(estimateRewards1[3], estimateRewards1[3].div(100));
      expect(estimateRewards2[4]).to.be.closeTo(estimateRewards1[4], estimateRewards1[4].div(100));
      expect(estimateRewards2[5]).to.be.closeTo(estimateRewards1[5], estimateRewards1[5].div(100));
      expect(estimateRewards2[6]).to.be.closeTo(estimateRewards1[6], estimateRewards1[6].div(100));
      expect(estimateRewards2[7]).to.be.closeTo(estimateRewards1[7], estimateRewards1[7].div(100));
    });
    it('Pending rewards become zero if a new user leaves right after depositing', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      await upgradeRD();
      console.log('RD upgraded !');
      console.log('Estimating rewards 2...');
      console.log('Joining garden by new deposit in course....');
      await gardenContract
        .connect(wallets[0])
        .deposit(eth(2000), eth(1000), wallets[0].getAddress(), false, { gasPrice: 0 });
      console.log('Increase 1 block...');
      await increaseBlock(1);
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      console.log('WithdrawAll in course....');
      // The first checkpoint is created for the user -> we then know prev balance
      await gardenContract
        .connect(wallets[0])
        .withdraw(await gardenContract.balanceOf(wallets[0].address), 1, wallets[0].getAddress(), false, ADDRESS_ZERO, {
          gasPrice: 0,
        });
      console.log('Estimating rewards 3...');
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      console.log('Increasing time...');
      await increaseTime(1);
      const [, , estimateRewards4] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      console.log('estimateRewards 1', estimateRewards1.toString());
      console.log('estimateRewards 2', estimateRewards2.toString());
      console.log('estimateRewards 3', estimateRewards3.toString());
      console.log('estimateRewards 4', estimateRewards4.toString());
      // mining is delivering more BABL along the time
      // new blocks has less profit in this example
      expect(estimateRewards4[0])
        .to.be.eq(estimateRewards3[0])
        .to.be.eq(estimateRewards2[0])
        .to.be.eq(estimateRewards1[0])
        .to.be.eq(0);
      expect(estimateRewards4[1])
        .to.be.eq(estimateRewards3[1])
        .to.be.eq(estimateRewards2[1])
        .to.be.eq(estimateRewards1[1])
        .to.be.eq(0);
      expect(estimateRewards4[2])
        .to.be.eq(estimateRewards3[2])
        .to.be.eq(estimateRewards2[2])
        .to.be.eq(estimateRewards1[2])
        .to.be.eq(0);
      expect(estimateRewards4[3])
        .to.be.eq(estimateRewards3[3])
        .to.be.eq(estimateRewards2[3])
        .to.be.eq(estimateRewards1[3])
        .to.be.eq(0);
      expect(estimateRewards4[4]).to.be.eq(estimateRewards1[4]).to.be.eq(0); // LP BABL is zero before deposit and after withdrawAll
      expect(estimateRewards4[5]).to.be.eq(estimateRewards1[5]).to.be.eq(0); // Total BABL is zero before deposit and after withdrawAll
      expect(estimateRewards4[6])
        .to.be.eq(estimateRewards3[6])
        .to.be.eq(estimateRewards2[6])
        .to.be.eq(estimateRewards1[6])
        .to.be.eq(0);
      expect(estimateRewards4[7])
        .to.be.eq(estimateRewards3[7])
        .to.be.eq(estimateRewards2[7])
        .to.be.eq(estimateRewards1[7])
        .to.be.eq(0);
      expect(estimateRewards3[4]).to.be.gt(estimateRewards2[4]).to.be.gt(0);
      expect(estimateRewards2[4]).to.be.eq(estimateRewards2[5]).to.be.gt(0);
      expect(estimateRewards3[4]).to.be.eq(estimateRewards3[5]).to.be.gt(0);
    });
  });
});
