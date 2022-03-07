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
    // Only user in specific tests
    // To use it, remember to disable the garden upgrade at deploy script
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
      gardenContract = await ethers.getContractAt('IGarden', arkadGarden);
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
      const rewards2 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
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
      const rewards2 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
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
      await upgradeRD();
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), { gasPrice: 0 });
      await increaseTime(1);
      const rewards2 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
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
      await upgradeRD();
      await gardenContract.connect(gardenMember).deposit(eth(2000), eth(1000), gardenMember.address, { gasPrice: 0 });
      await increaseTime(1);
      const rewards2 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
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
    it('Unclaimed rewards of garden creator are equivalent after new deposit by a new user (big deposit)', async () => {
      const rewards1 = await distributor.getRewards(arkadGarden, await gardenContract.creator(), [...strategies]);
      await upgradeRD();
      await gardenContract
        .connect(wallets[0])
        .deposit(eth(200000), eth(1000), wallets[0].getAddress(), { gasPrice: 0 });
      await increaseTime(1);
      const rewards2 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
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
    it('Unclaimed rewards (old garden strategies) are 0 for new users depositing into a garden', async () => {
      await upgradeRD();
      const rewards1 = await distributor.getRewards(arkadGarden, wallets[0].address, [...strategies]);
      await gardenContract.connect(wallets[0]).deposit(eth(2000), eth(1000), wallets[0].getAddress(), { gasPrice: 0 });
      const rewards2 = await distributor.getRewards(arkadGarden, wallets[0].address, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, wallets[0].address, [...strategies]);
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
      await upgradeRD();
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), { gasPrice: 0 });
      await increaseTime(1);
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), { gasPrice: 0 });
      await increaseTime(1);
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(200000), eth(1000), creatorWallet.getAddress(), { gasPrice: 0 });
      await increaseTime(1);
      const rewards2 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
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
      await upgradeRD();
      await gardenContract.connect(gardenMember).deposit(eth(2000), eth(1000), gardenMember.address, { gasPrice: 0 });
      await increaseTime(1);
      await gardenContract.connect(gardenMember).deposit(eth(2000), eth(1000), gardenMember.address, { gasPrice: 0 });
      await increaseTime(1);
      await gardenContract.connect(gardenMember).deposit(eth(200000), eth(1000), gardenMember.address, { gasPrice: 0 });
      await increaseTime(1);
      const rewards2 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      // unclaimed rewards that are always deterministic (strategist/stewards -> both profit and BABL)
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(rewards1[0]);
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(rewards1[1]);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(rewards1[2]);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(rewards1[3]);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(rewards1[6]);
      // RD upgrade is smooth (no slippage) as c-power is kept for old strategies but it might produce slippage in the future
      // User deposit has a self-migration mechanism so it is reduced a bit only once and then its % share increase along the time
      expect(rewards2[4]).to.be.closeTo(rewards1[4], rewards1[4].div(100)); // 1%
      expect(rewards2[5]).to.be.closeTo(rewards1[5], rewards1[5].div(100));
      expect(rewards3[4]).to.be.closeTo(rewards2[4], rewards2[4].div(3)); // 33% slippage
      expect(rewards3[5]).to.be.closeTo(rewards2[5], rewards2[5].div(3));
    });
    it('Unclaimed rewards are equivalent after a partial withdrawal by creator (slippage in the future due to old c.power)', async () => {
      const rewards1 = await distributor.getRewards(arkadGarden, await gardenContract.creator(), [...strategies]);
      await upgradeRD();
      await increaseTime(1);
      const rewards2 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      // The first checkpoint is created for the user -> we then know prev balance
      await gardenContract
        .connect(creatorWallet)
        .withdraw(eth(500), 1, creatorWallet.getAddress(), false, ADDRESS_ZERO, { gasPrice: 0 });
      await increaseTime(1);
      const rewards3 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards4 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
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
    it('Unclaimed rewards can still be claimed after withdrawAll by garden member (slippage limited to the self-migration)', async () => {
      const rewards1 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      await upgradeRD();
      await increaseTime(1);
      const rewards2 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
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
      const rewards3 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards4 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      await gardenContract.connect(gardenMember).claimReturns([...strategies]); // claim all
      const rewards5 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
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
      await upgradeRD();
      await increaseTime(1);
      const rewards2 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
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
      const rewards3 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards4 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      await increaseTime(1);
      await gardenContract
        .connect(gardenMember)
        .deposit(eth(10000), eth(1000), gardenMember.getAddress(), { gasPrice: 0 });
      await increaseTime(1);
      const rewards5 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      // unclaimed rewards that are always deterministic (strategist/stewards -> both profit and BABL)
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(rewards1[0]);
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(rewards1[1]);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(rewards1[2]);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(rewards1[3]);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(rewards1[6]);
      // RD upgrade is smooth (no slippage) as c-power is kept for old strategies but it might produce slippage in the future
      expect(rewards2[4]).to.be.closeTo(rewards1[4], rewards1[4].div(100)); // 1%
      expect(rewards2[5]).to.be.closeTo(rewards1[5], rewards1[5].div(100)); // 1%
      // After withdrawAll it is still equivalent and claimable
      expect(rewards3[4]).to.be.closeTo(rewards2[4], rewards2[4].div(100)); // 1%
      expect(rewards3[5]).to.be.closeTo(rewards2[5], rewards2[5].div(100)); // 1%
      // Time passes (old c.power produce some slippage)
      expect(rewards4[4]).to.be.closeTo(rewards3[4], rewards3[4].div(3)); // 33% slippage due to old c-power time
      expect(rewards4[5]).to.be.closeTo(rewards3[5], rewards3[5].div(3)); // 33% slippage due to old c-power time
      // After new deposit it is still equivalent (no additional impact on top of the slippage)
      expect(rewards5[4]).to.be.closeTo(rewards4[4], rewards4[4].div(100)); // 1%
      expect(rewards5[5]).to.be.closeTo(rewards4[5], rewards4[5].div(100)); // 1%
    });
    it('Pending rewards are equivalent if no new deposit of garden creator', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await upgradeRD();
      await increaseTime(1);
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
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
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, gardenMember.address);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, gardenMember.address);
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
    it('Pending rewards are equivalent if no new deposit of garden creator but a new member depositing a big amount', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await upgradeRD();
      await increaseTime(1);
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await increaseTime(1);
      await gardenContract
        .connect(wallets[0])
        .deposit(eth(200000), eth(1000), wallets[0].getAddress(), { gasPrice: 0 });
      await increaseTime(1);
      const [, , estimateRewards4] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
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

      // New deposit only affect a bit due to old c-power
      expect(estimateRewards4[4]).to.be.closeTo(estimateRewards3[4], estimateRewards3[4].div(25));
      expect(estimateRewards4[5]).to.be.closeTo(estimateRewards3[5], estimateRewards3[5].div(25));
    });
    it('Pending rewards are zero if a new user has not joined yet', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      await upgradeRD();
      await increaseTime(1);
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      expect(estimateRewards3[0]).to.be.eq(estimateRewards2[0]).to.be.eq(estimateRewards1[0]).to.be.eq(0);
      expect(estimateRewards3[1]).to.be.eq(estimateRewards2[1]).to.be.eq(estimateRewards1[1]).to.be.eq(0);
      expect(estimateRewards3[2]).to.be.eq(estimateRewards2[2]).to.be.eq(estimateRewards1[2]).to.be.eq(0);
      expect(estimateRewards3[3]).to.be.eq(estimateRewards2[3]).to.be.eq(estimateRewards1[3]).to.be.eq(0);
      expect(estimateRewards3[4]).to.be.eq(estimateRewards2[4]).to.be.eq(estimateRewards1[4]).to.be.eq(0);
      expect(estimateRewards3[5]).to.be.eq(estimateRewards2[5]).to.be.eq(estimateRewards1[5]).to.be.eq(0);
      expect(estimateRewards3[6]).to.be.eq(estimateRewards2[6]).to.be.eq(estimateRewards1[6]).to.be.eq(0);
      expect(estimateRewards3[7]).to.be.eq(estimateRewards2[7]).to.be.eq(estimateRewards1[7]).to.be.eq(0);
    });
    it('Pending rewards become deterministic on first deposit and it will will only add proportional value to the creator', async () => {
      // Note: there is slippage after depositing due to the user self-migrate from c.power to checkpoints by its deposit
      // also the new value is not accounting 100% yet
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await upgradeRD();
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await increaseTime(1);
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), { gasPrice: 0 });
      await increaseTime(1);
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const [, , estimateRewards4] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
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
      // The reduction is based on real adjustment of user avg balance
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
    it('Pending rewards are equivalent for Arkad after a new big deposit of a new joining member (it does affect only a bit)', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await upgradeRD();
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await increaseTime(1);
      await gardenContract
        .connect(wallets[0])
        .deposit(eth(200000), eth(1000), wallets[0].getAddress(), { gasPrice: 0 });
      await increaseTime(1);
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const [, , estimateRewards4] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
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

      // the new big deposit by a different user is affecting just a bit to current user
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
    it('Pending rewards are equivalent for 2 beta users after a new big deposit of a new joining member', async () => {
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
      await gardenContract
        .connect(wallets[0])
        .deposit(eth(200000), eth(1000), wallets[0].getAddress(), { gasPrice: 0 });
      await increaseTime(1);
      const [, , estimateRewards3Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards3GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards3NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const [, , estimateRewards4Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards4GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards4NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      // No impact at all to previous users for new users joining
      expect(estimateRewards4Creator[4])
        .to.be.gt(estimateRewards3Creator[4])
        .to.be.gt(estimateRewards2Creator[4])
        .to.be.gt(estimateRewards1Creator[4]);
      expect(estimateRewards4GardenMember[4])
        .to.be.gt(estimateRewards3GardenMember[4])
        .to.be.gt(estimateRewards2GardenMember[4])
        .to.be.gt(estimateRewards1GardenMember[4]);
      expect(estimateRewards4NewUser[4])
        .to.be.gt(estimateRewards3NewUser[4])
        .to.be.gt(estimateRewards2NewUser[4])
        .to.be.gt(estimateRewards1NewUser[4]);
      // zero if not a garden member
      expect(estimateRewards2NewUser[4]).to.be.eq(estimateRewards1NewUser[4]).to.be.eq(0);
      // Despite it is a big deposit, it gets just proportional
      expect(estimateRewards3NewUser[4]).to.be.lt(estimateRewards3GardenMember[4]);
    });
    it('Pending rewards are equivalent for 2 beta users after they both make a new deposit + a normal deposit of a new joining member (big slippage for garden member)', async () => {
      // Note: the slippage to gardenMember is produced by its own deposit, not by someone else
      // The reason is that after first deposit users are migrated from old c.power to checkpoints but only for live strategies
      // The correction takes place during the initial checkpoint
      // unclaimed (previous strategies) remain the same
      // On the other hand bigger balances are not impacted more than 7%
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
      await gardenContract.connect(creatorWallet).deposit(eth(2000), eth(1000), creator, { gasPrice: 0 });
      await increaseTime(1);
      const [, , estimateRewards3Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards3GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards3NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      await increaseTime(1);
      await gardenContract.connect(gardenMember).deposit(eth(2000), eth(1000), gardenMember.address, { gasPrice: 0 });
      await increaseTime(1);
      const [, , estimateRewards4Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards4GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards4NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      await increaseTime(1);
      await gardenContract.connect(wallets[0]).deposit(eth(6000), eth(1000), wallets[0].getAddress(), { gasPrice: 0 });
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
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const [, , estimateRewards6Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards6GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards6NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      // beta creator is equivalent until its first deposit using checkpoints
      expect(estimateRewards2Creator[4]).to.be.gt(estimateRewards1Creator[4]);
      // % share is reduced a bit by its own deposit, then it follows the new increasing path
      expect(estimateRewards3Creator[4]).to.be.lt(estimateRewards2Creator[4]);
      expect(estimateRewards3Creator[4]).to.be.closeTo(estimateRewards2Creator[4], estimateRewards2Creator[4].div(13)); // 7%
      expect(estimateRewards6Creator[4])
        .to.be.gt(estimateRewards5Creator[4])
        .to.be.gt(estimateRewards4Creator[4])
        .to.be.gt(estimateRewards3Creator[4]);
      // beta garden member is equivalent until its first deposit using checkpoints
      expect(estimateRewards3GardenMember[4])
        .to.be.closeTo(estimateRewards2GardenMember[4], estimateRewards2GardenMember[4].div(1000))
        .to.be.gt(estimateRewards1GardenMember[4]);
      // % share is reduced a bit by its own deposit, then it follows the new increasing path
      expect(estimateRewards5GardenMember[4]).to.be.lt(estimateRewards4GardenMember[4]);
      // BIG SLIPPAGE aprox. 70% caused by its own deposit (it goes from c.power track to checkpoints track)
      // The slipagge is higher for those users with more time in the garden and lower balances
      // Once the migration occur, it only happens once, no new migration paths might be needed
      expect(estimateRewards4GardenMember[4]).to.be.closeTo(
        estimateRewards3GardenMember[4].mul(306).div(1000),
        estimateRewards3GardenMember[4].div(100),
      ); // aprox. 70% very big slippage caused by its own deposit (reseting its c.power into checkpoints)
      expect(estimateRewards6GardenMember[4]).to.be.gt(estimateRewards5GardenMember[4]);
      // New user - deterministic path
      expect(estimateRewards6NewUser[4])
        .to.be.gt(estimateRewards5NewUser[4])
        .to.be.gt(estimateRewards4NewUser[4])
        .to.be.gt(estimateRewards3NewUser[4])
        .to.be.gt(estimateRewards2NewUser[4])
        .to.be.gt(estimateRewards1NewUser[4]);
      // zero if not a garden member
      expect(estimateRewards4NewUser[4])
        .to.be.eq(estimateRewards3NewUser[4])
        .to.be.eq(estimateRewards2NewUser[4])
        .to.be.eq(estimateRewards1NewUser[4])
        .to.be.eq(0);
      // Despite it is a big deposit, it gets just proportional
      expect(estimateRewards5NewUser[4]).to.be.lt(estimateRewards5GardenMember[4]);
      // new user 6K still do not pass garden member (with lower balance)
      expect(estimateRewards6NewUser[4]).to.be.lt(estimateRewards6GardenMember[4]);
      expect(await gardenContract.balanceOf(wallets[0].address)).to.be.gt(
        await gardenContract.balanceOf(gardenMember.address),
      );
    });
    it('Pending rewards have slippage when self-migrating 2 beta users after they both make a new deposit + a BIG 200K deposit of a new joining member', async () => {
      // Note: the slippage to gardenMember by its own deposit, not by someone else
      // The reason is that after first deposit users are migrated from old c.power to checkpoints but only for live strategies
      // unclaimed (previous strategies) remain the same
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
      await gardenContract.connect(creatorWallet).deposit(eth(2000), eth(1000), creator, { gasPrice: 0 });
      await increaseTime(1);
      const [, , estimateRewards3Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards3GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards3NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      await gardenContract.connect(gardenMember).deposit(eth(2000), eth(1000), gardenMember.address, { gasPrice: 0 });
      const [, , estimateRewards4Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards4GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards4NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      await increaseTime(1);
      await gardenContract
        .connect(wallets[0])
        .deposit(eth(200000), eth(1000), wallets[0].getAddress(), { gasPrice: 0 });
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
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const [, , estimateRewards6Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards6GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards6NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      // beta creator is equivalent until its first deposit using checkpoints
      expect(estimateRewards2Creator[4]).to.be.gt(estimateRewards1Creator[4]);
      // % share is reduced a bit by its own deposit, then it follows the new increasing path
      expect(estimateRewards3Creator[4]).to.be.lt(estimateRewards2Creator[4]);
      // Slippage (aprox 7%) for creator after self-migrating from c.power to new checkpoints path
      expect(estimateRewards3Creator[4]).to.be.closeTo(estimateRewards2Creator[4], estimateRewards2Creator[4].div(13)); // 7%
      expect(estimateRewards6Creator[4])
        .to.be.gt(estimateRewards5Creator[4])
        .to.be.gt(estimateRewards4Creator[4])
        .to.be.gt(estimateRewards3Creator[4]);
      // beta garden member is equivalent until its first deposit using checkpoints
      expect(estimateRewards3GardenMember[4])
        .to.be.closeTo(estimateRewards2GardenMember[4], estimateRewards2GardenMember[4].div(100))
        .to.be.closeTo(estimateRewards1GardenMember[4], estimateRewards1GardenMember[4].div(100));
      // % share is reduced by its own deposit, then it follows the new increasing (deterministic) path
      expect(estimateRewards5GardenMember[4]).to.be.lt(estimateRewards4GardenMember[4]);
      // BIG SLIPPAGE (aprox. 73%) caused by its own deposit (it goes from c.power track to checkpoints track)
      // The slipagge is higher for those users with more time in the garden and lower balances
      // Where time had been an advantage vs. balance
      // Once the migration occur, it only happens once, no new migration paths might be needed
      expect(estimateRewards5GardenMember[4]).to.be.closeTo(
        estimateRewards4GardenMember[4].mul(277).div(1000),
        estimateRewards4GardenMember[4].div(100),
      ); // very big slippage caused by its own deposit (reseting its c.power into checkpoints)
      expect(estimateRewards6GardenMember[4]).to.be.gt(estimateRewards5GardenMember[4]);
      // New user - deterministic path
      expect(estimateRewards6NewUser[4])
        .to.be.gt(estimateRewards5NewUser[4])
        .to.be.gt(estimateRewards4NewUser[4])
        .to.be.gt(estimateRewards3NewUser[4])
        .to.be.gt(estimateRewards2NewUser[4])
        .to.be.gt(estimateRewards1NewUser[4]);
      // zero if not a garden member
      expect(estimateRewards4NewUser[4])
        .to.be.eq(estimateRewards3NewUser[4])
        .to.be.eq(estimateRewards2NewUser[4])
        .to.be.eq(estimateRewards1NewUser[4])
        .to.be.eq(0);
      // Despite it is a big deposit, it gets just proportional
      expect(estimateRewards5NewUser[4]).to.be.lt(estimateRewards5GardenMember[4]);
      // new user 200K pass garden member but not garden creator yet due to proportional balance
      expect(estimateRewards6NewUser[4]).to.be.gt(estimateRewards6GardenMember[4]).to.be.lt(estimateRewards6Creator[4]);
      expect(await gardenContract.balanceOf(wallets[0].address)).to.be.gt(await gardenContract.balanceOf(creator));
    });
    it('Filter a hack if avgGarden > balanceEnd to get higher % ', async () => {
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
      await gardenContract.connect(creatorWallet).deposit(eth(2000), eth(1000), creator, { gasPrice: 0 });
      await increaseTime(1);
      const [, , estimateRewards3Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards3GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards3NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      await gardenContract.connect(gardenMember).deposit(eth(2000), eth(1000), gardenMember.address, { gasPrice: 0 });
      await increaseTime(1);
      const [, , estimateRewards4Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards4GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards4NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      await increaseTime(1);
      await gardenContract
        .connect(wallets[0])
        .deposit(eth(200000), eth(1000), wallets[0].getAddress(), { gasPrice: 0 });
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
      await increaseTime(1);
      await gardenContract
        .connect(creatorWallet)
        .withdraw(
          (await gardenContract.balanceOf(creatorWallet.address)).sub(eth(10000)),
          1,
          creatorWallet.getAddress(),
          false,
          ADDRESS_ZERO,
          { gasPrice: 0 },
        );
      await increaseTime(1);
      const [, , estimateRewards6Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards6GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards6NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      expect(estimateRewards6Creator[4])
        .to.be.lt(estimateRewards5Creator[4])
        .to.be.lt(estimateRewards4Creator[4])
        .to.be.lt(estimateRewards3Creator[4])
        .to.be.lt(estimateRewards2Creator[4])
        .to.be.lt(estimateRewards1Creator[4]);
    });
    it('Pending rewards has some slippage for 2 beta users after a new deposit from them + x2 a big deposit of a new joining member (before and after upgrades)', async () => {
      // Note: this test need to disable garden upgrade at deploy.js
      // Note 2: the main slippage is only due to each own user deposit -> as they pass from c.power to current balance path
      // The garden will be upgraded after a first big deposit
      // A new member joins with a big deposit and we want him to be using old SC
      await gardenContract
        .connect(wallets[0])
        .deposit(eth(200000), eth(1000), wallets[0].getAddress(), { gasPrice: 0 });
      await increaseTime(1);
      const [, , estimateRewards1Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards1GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards1NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      await upgradeGarden();
      await upgradeRD();
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
      await gardenContract.connect(creatorWallet).deposit(eth(2000), eth(1000), creator, { gasPrice: 0 });
      await increaseTime(1);
      const [, , estimateRewards3Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards3GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards3NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      await gardenContract.connect(gardenMember).deposit(eth(2000), eth(1000), gardenMember.address, { gasPrice: 0 });
      await increaseTime(1);
      const [, , estimateRewards4Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards4GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards4NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      await gardenContract
        .connect(wallets[0])
        .deposit(eth(200000), eth(1000), wallets[0].getAddress(), { gasPrice: 0 });
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
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const [, , estimateRewards6Creator] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      const [, , estimateRewards6GardenMember] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        gardenMember.address,
      );
      const [, , estimateRewards6NewUser] = await viewerContract.getContributionAndRewards(
        arkadGarden,
        wallets[0].address,
      );
      // beta creator is equivalent until its first deposit using checkpoints
      expect(estimateRewards2Creator[4]).to.be.gt(estimateRewards1Creator[4]);
      // % share is reduced a bit by its own deposit, then it follows the new increasing path
      expect(estimateRewards3Creator[4]).to.be.lt(estimateRewards2Creator[4]);
      expect(estimateRewards3Creator[4]).to.be.closeTo(estimateRewards2Creator[4], estimateRewards2Creator[4].div(6)); // 16% slippage
      // Once it is migrated into checkpoints, it is a deterministic path
      expect(estimateRewards6Creator[4])
        .to.be.gt(estimateRewards5Creator[4])
        .to.be.gt(estimateRewards4Creator[4])
        .to.be.gt(estimateRewards3Creator[4]);

      // beta garden member is equivalent until its first deposit using checkpoints
      expect(estimateRewards3GardenMember[4])
        .to.be.gt(estimateRewards2GardenMember[4])
        .to.be.gt(estimateRewards1GardenMember[4]);
      // % share is reduced a bit by its own deposit, then it follows the new increasing path
      expect(estimateRewards4GardenMember[4]).to.be.lt(estimateRewards3GardenMember[4]);
      // BIG SLIPPAGE caused by its own deposit (it goes from c.power track to checkpoints track)
      // The slipagge is higher for those users with more time in the garden and lower balances
      // Once the migration occur, it only happens once, no new migration paths might be needed
      expect(estimateRewards4GardenMember[4]).to.be.closeTo(
        estimateRewards3GardenMember[4].mul(277).div(1000),
        estimateRewards3GardenMember[4].div(100),
      ); // aprox. 73% -> very big slippage caused by its own deposit (reseting its c.power into checkpoints)
      expect(estimateRewards6GardenMember[4])
        .to.be.gt(estimateRewards5GardenMember[4])
        .to.be.gt(estimateRewards4GardenMember[4]);
      // New user - deterministic path
      expect(estimateRewards6NewUser[4])
        .to.be.gt(estimateRewards5NewUser[4])
        .to.be.gt(estimateRewards4NewUser[4])
        .to.be.gt(estimateRewards3NewUser[4])
        .to.be.gt(estimateRewards2NewUser[4])
        .to.be.gt(estimateRewards1NewUser[4]);
      // non-zero as it is a garden member
      expect(estimateRewards1NewUser[4]).to.be.gt(0);
      // Despite it is a big deposit, it gets just proportional, so it still gets less than creator and garden member
      expect(estimateRewards4NewUser[4]).to.be.lt(estimateRewards4GardenMember[4]).to.be.lt(estimateRewards4Creator[4]);
      // new user 200K pass garden member and also garden creator yet due to proportional balance
      expect(estimateRewards5NewUser[4]).to.be.gt(estimateRewards5GardenMember[4]).to.be.gt(estimateRewards5Creator[4]);
    });
    it('Pending rewards are deterministic and implement firewall-ing for new deposit giving only proportional (multideposit by creator)', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await upgradeRD();
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), { gasPrice: 0 });
      await increaseTime(10);
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), { gasPrice: 0 });
      await increaseTime(10);
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), { gasPrice: 0 });
      await increaseTime(1);
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const [, , estimateRewards4] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
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
      await gardenContract.connect(wallets[0]).deposit(eth(2000), eth(1000), wallets[0].getAddress(), { gasPrice: 0 });
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
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
      // The first checkpoint is created for the user -> we then know prev balance
      await gardenContract
        .connect(creatorWallet)
        .withdraw(eth(1000), 1, creatorWallet.getAddress(), false, ADDRESS_ZERO, { gasPrice: 0 });
      await increaseTime(1);
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
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
      expect(estimateRewards2[4]).to.be.closeTo(estimateRewards1[4], estimateRewards1[4].div(13)); // 7% slippage
      expect(estimateRewards2[5]).to.be.closeTo(estimateRewards1[5], estimateRewards1[5].div(25)); // 4% slippage
      expect(estimateRewards2[6]).to.be.closeTo(estimateRewards1[6], estimateRewards1[6].div(100));
      expect(estimateRewards2[7]).to.be.closeTo(estimateRewards1[7], estimateRewards1[7].div(25)); // 4% slippage
    });
    it('LP Pending rewards become zero after withdrawalAll (steward rewards continue increasing...)', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, gardenMember.address);
      await upgradeRD();
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, gardenMember.address);
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
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, gardenMember.address);
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
      await gardenContract.connect(wallets[0]).deposit(eth(2000), eth(1000), wallets[0].getAddress(), { gasPrice: 0 });
      await increaseBlock(1);
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      // The first checkpoint is created for the user -> we then know prev balance
      await gardenContract
        .connect(wallets[0])
        .withdraw(await gardenContract.balanceOf(wallets[0].address), 1, wallets[0].getAddress(), false, ADDRESS_ZERO, {
          gasPrice: 0,
        });
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      await increaseTime(1);
      const [, , estimateRewards4] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
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
