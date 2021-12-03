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

      // await increaseTime(1000);

      wallets = await createWallets(1, {
        tokens: [addresses.tokens.DAI, addresses.tokens.ETH],
        amounts: [eth(10000), eth(900)],
      });
      // console.log(wallets[0].address);
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
      await fund([creator, wallets[0].address], { tokens: [addresses.tokens.DAI] });
      await reserveContract.connect(creatorWallet).approve(arkadGarden, eth(9999999), { gasPrice: 0 });
      await reserveContract.connect(wallets[0]).approve(gardenContract.address, eth(9999999), { gasPrice: 0 });
      // await increaseBlock(1);
    });

    it('Unclaimed rewards are equivalent if no new deposit (slippage due to old c.power)', async () => {
      const rewards1 = await distributor.getRewards(arkadGarden, await gardenContract.creator(), [...strategies]);
      await upgradeRD();
      console.log('RD upgraded !');
      const rewards2 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      console.log('rewards 1', await normalizeToken(rewards1[4]).toString());
      console.log('rewards 2', await normalizeToken(rewards2[4]).toString());
      console.log('rewards 3', await normalizeToken(rewards3[4]).toString());
      // unclaimed rewards are always deterministic
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(rewards1[0]); // needs block number after last RD upgrade
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(rewards1[1]);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(rewards1[2]);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(rewards1[3]);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(rewards1[6]);
      // unclaimed LP rewards with slippage due to old contributor power not deterministic
      // New RD upgrade makes deterministic all LP rewards for all finished strategies who has endGardenSupply set
      expect(rewards2[4]).to.be.closeTo(rewards1[4], rewards1[4].div(100)); // 1%
      expect(rewards2[5]).to.be.closeTo(rewards1[5], rewards1[5].div(100));
      expect(rewards3[4]).to.be.closeTo(rewards2[4], rewards2[4].div(20)); // 5%
      expect(rewards3[5]).to.be.closeTo(rewards2[5], rewards2[5].div(20));
    });
    it('Unclaimed rewards are kept with some slippage after new deposit', async () => {
      const rewards1 = await distributor.getRewards(arkadGarden, await gardenContract.creator(), [...strategies]);
      console.log('---upgrading RD...');
      await upgradeRD();
      console.log('---RD upgraded !');
      console.log('----- BEFORE DEPOSIT-----');
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), false, { gasPrice: 0 });
      const rewards2 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      console.log('----- AFTER DEPOSIT-----');
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      console.log('rewards 1', await normalizeToken(rewards1[4]).toString());
      console.log('rewards 2', await normalizeToken(rewards2[4]).toString());
      console.log('rewards 3', await normalizeToken(rewards3[4]).toString());
      // unclaimed rewards deterministic
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(rewards1[0]);
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(rewards1[1]);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(rewards1[2]);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(rewards1[3]);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(rewards1[6]);
      // unclaimed LP rewards with slippage due to old contributor power not deterministic
      // New RD upgrade makes deterministic all LP rewards for all finished strategies who has endGardenSupply set
      expect(rewards2[4]).to.be.closeTo(rewards1[4], rewards1[4].div(100)); // 1%
      expect(rewards2[5]).to.be.closeTo(rewards1[5], rewards1[5].div(100));
      expect(rewards3[4]).to.be.closeTo(rewards2[4], rewards2[4].div(20)); // 5% slippage
      expect(rewards3[5]).to.be.closeTo(rewards2[5], rewards2[5].div(20)); // 5% slippage
    });
    it('Unclaimed rewards are 0 if new user just deposit', async () => {
      console.log('---upgrading RD...');
      await upgradeRD();
      console.log('---RD upgraded !');
      await gardenContract
        .connect(wallets[0])
        .deposit(eth(2000), eth(1000), wallets[0].getAddress(), false, { gasPrice: 0 });
      const rewards2 = await distributor.getRewards(arkadGarden, wallets[0].address, [...strategies]);
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, wallets[0].address, [...strategies]);
      console.log('rewards 2', await normalizeToken(rewards2[4]).toString());
      console.log('rewards 3', await normalizeToken(rewards3[4]).toString());
      // unclaimed rewards are 0 and deterministic
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(0);
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(0);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(0);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(0);
      expect(rewards3[4]).to.be.eq(rewards2[4]).to.be.eq(0);
      expect(rewards3[5]).to.be.eq(rewards2[5]).to.be.eq(0);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(0);
      expect(rewards3[7]).to.be.eq(rewards2[7]).to.be.eq(0);
    });
    it('Unclaimed rewards are kept with some slippage after partial withdraw', async () => {
      console.log('----Getting rewards 1....');
      const rewards1 = await distributor.getRewards(arkadGarden, await gardenContract.creator(), [...strategies]);
      console.log('----Upgrading RD....');
      await upgradeRD();
      console.log('----Getting rewards 2....');
      const rewards2 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      console.log('----Withdrawing....');
      // The first checkpoint is created for the user -> we then know prev balance
      await gardenContract
        .connect(creatorWallet)
        .withdraw(eth(500), 1, creatorWallet.getAddress(), false, ADDRESS_ZERO, { gasPrice: 0 });
      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      console.log('----Getting rewards 3....');
      const rewards3 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      console.log('rewards 1', await normalizeToken(rewards1[4]).toString());
      console.log('rewards 2', await normalizeToken(rewards2[4]).toString());
      console.log('rewards 3', await normalizeToken(rewards3[4]).toString());
      // unclaimed rewards deterministic
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(rewards1[0]);
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(rewards1[1]);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(rewards1[2]);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(rewards1[3]);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(rewards1[6]);
      // unclaimed LP rewards with slippage due to old contributor power not deterministic
      // New RD upgrade makes deterministic all LP rewards for all finished strategies who has endGardenSupply set
      expect(rewards2[4]).to.be.closeTo(rewards1[4], rewards1[4].div(100));
      expect(rewards2[5]).to.be.closeTo(rewards1[5], rewards1[5].div(100));
      expect(rewards3[4]).to.be.closeTo(rewards2[4], rewards2[4].div(20));
      expect(rewards3[5]).to.be.closeTo(rewards2[5], rewards2[5].div(20));
    });
    it('Unclaimed rewards can be claimed after withdrawAll (slippage based on previous balance)', async () => {
      const rewards1 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      console.log('---upgrading RD...');
      await upgradeRD();
      console.log('---RD upgraded !');
      const rewards2 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
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
      const rewards3 = await distributor.getRewards(arkadGarden, gardenMember.address, [...strategies]);
      console.log('rewards 1', rewards1[4].toString());
      console.log('rewards 2', rewards2[4].toString());
      console.log('rewards 3', rewards3[4].toString());
      // unclaimed rewards deterministic
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(rewards1[0]);
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(rewards1[1]);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(rewards1[2]);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(rewards1[3]);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(rewards1[6]);
      // unclaimed LP rewards with slippage due to old contributor power not deterministic
      expect(rewards2[4]).to.be.closeTo(rewards1[4], rewards1[4].div(100)); // 1%
      expect(rewards2[5]).to.be.closeTo(rewards1[5], rewards1[5].div(100)); // 1%
      expect(rewards3[4]).to.be.closeTo(rewards2[4], rewards2[4].div(3)); // 33% slippage after withdrawAll
      expect(rewards3[5]).to.be.closeTo(rewards2[5], rewards2[5].div(3)); // 33% slippage after withdrawAll
    });
    it('Pending rewards are equivalent if no new deposit (slippage only after upgrade due to old c.power)', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await upgradeRD();
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
      // new blocks has less profit in this example
      expect(estimateRewards3[0]).to.be.gt(estimateRewards2[0]).to.be.gt(estimateRewards1[0]);
      expect(estimateRewards3[1]).to.be.lt(estimateRewards2[1]).to.be.lt(estimateRewards1[1]);
      expect(estimateRewards3[2]).to.be.gt(estimateRewards2[2]).to.be.gt(estimateRewards1[2]);
      expect(estimateRewards3[3]).to.be.lt(estimateRewards2[3]).to.be.lt(estimateRewards1[3]);
      expect(estimateRewards3[4]).to.be.gt(estimateRewards2[4]).to.be.gt(estimateRewards1[4]); // after upgrade we pass from c-power to deterministic so it decreases a bit
      expect(estimateRewards3[5]).to.be.gt(estimateRewards2[5]).to.be.gt(estimateRewards1[5]); // after upgrade we pass from c-power to deterministic so it decreases a bit
      expect(estimateRewards3[6]).to.be.lt(estimateRewards2[6]).to.be.lt(estimateRewards1[6]);
      expect(estimateRewards3[7]).to.be.gt(estimateRewards2[7]).to.be.gt(estimateRewards1[7]); // after upgrade we pass from c-power to deterministic so it decreases a bit
      expect(estimateRewards2[0]).to.be.closeTo(estimateRewards1[0], estimateRewards1[0].div(100)); // 1%
      expect(estimateRewards2[1]).to.be.closeTo(estimateRewards1[1], estimateRewards1[1].div(100)); // 1%
      expect(estimateRewards2[2]).to.be.closeTo(estimateRewards1[2], estimateRewards1[2].div(100)); // 1%
      expect(estimateRewards2[3]).to.be.closeTo(estimateRewards1[3], estimateRewards1[3].div(100)); // 1%
      expect(estimateRewards2[4]).to.be.closeTo(estimateRewards1[4], estimateRewards1[4].div(15)); // 7% slippage due to passing from c-power to deterministic
      expect(estimateRewards2[5]).to.be.closeTo(estimateRewards1[5], estimateRewards1[5].div(20)); // 5% affected by above
      expect(estimateRewards2[6]).to.be.closeTo(estimateRewards1[6], estimateRewards1[6].div(100)); // 1%
      expect(estimateRewards2[7]).to.be.closeTo(estimateRewards1[7], estimateRewards1[7].div(20)); // 5% affected by above
    });
    it.only('Pending rewards are deterministic and implement firewalling for new deposit giving only proportional', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await upgradeRD();
      console.log('RD upgraded !');
      console.log('New deposit in course....');
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), false, { gasPrice: 0 });
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
      expect(estimateRewards3[4]).to.be.gt(estimateRewards2[4]).to.be.gt(estimateRewards1[4]); // after upgrade we pass from c-power to deterministic so it decreases a bit
      expect(estimateRewards3[5]).to.be.gt(estimateRewards2[5]).to.be.gt(estimateRewards1[5]); // after upgrade we pass from c-power to deterministic so it decreases a bit
      expect(estimateRewards3[6]).to.be.lt(estimateRewards2[6]).to.be.lt(estimateRewards1[6]);
      expect(estimateRewards3[7]).to.be.gt(estimateRewards2[7]).to.be.gt(estimateRewards1[7]); // after upgrade we pass from c-power to deterministic so it decreases a bit
      expect(estimateRewards2[0]).to.be.closeTo(estimateRewards1[0], estimateRewards1[0].div(100)); // 1%
      expect(estimateRewards2[1]).to.be.closeTo(estimateRewards1[1], estimateRewards1[1].div(100)); // 1%
      expect(estimateRewards2[2]).to.be.closeTo(estimateRewards1[2], estimateRewards1[2].div(100)); // 1%
      expect(estimateRewards2[3]).to.be.closeTo(estimateRewards1[3], estimateRewards1[3].div(100)); // 1%
      expect(estimateRewards2[4]).to.be.closeTo(estimateRewards1[4], estimateRewards1[4].div(100)); // 7% slippage due to passing from c-power to deterministic
      expect(estimateRewards2[5]).to.be.closeTo(estimateRewards1[5], estimateRewards1[5].div(100)); // 5% affected by above
      expect(estimateRewards2[6]).to.be.closeTo(estimateRewards1[6], estimateRewards1[6].div(100)); // 1%
      expect(estimateRewards2[7]).to.be.closeTo(estimateRewards1[7], estimateRewards1[7].div(100)); // 5% affected by above
    });
    it('Pending rewards are deterministic != 0 for a new user and implement firewalling giving only proportional vs. strategy start time', async () => {
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
    it('Pending rewards are deterministic and react for new withdrawals before strategy finalization', async () => {
      const [, , estimateRewards1] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      await upgradeRD();
      console.log('RD upgraded !');
      console.log('Partial withdrawing in course....');
      // The first checkpoint is created for the user -> we then know prev balance
      await gardenContract
        .connect(creatorWallet)
        .withdraw(eth(10000), 1, creatorWallet.getAddress(), false, ADDRESS_ZERO, { gasPrice: 0 });
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
      expect(estimateRewards3[4]).to.be.gt(estimateRewards2[4]).to.be.gt(estimateRewards1[4]); // after upgrade we pass from c-power to deterministic so it decreases a bit
      expect(estimateRewards3[5]).to.be.gt(estimateRewards2[5]).to.be.gt(estimateRewards1[5]); // after upgrade we pass from c-power to deterministic so it decreases a bit
      expect(estimateRewards3[6]).to.be.lt(estimateRewards2[6]).to.be.lt(estimateRewards1[6]);
      expect(estimateRewards3[7]).to.be.gt(estimateRewards2[7]).to.be.gt(estimateRewards1[7]); // after upgrade we pass from c-power to deterministic so it decreases a bit
      expect(estimateRewards2[0]).to.be.closeTo(estimateRewards1[0], estimateRewards1[0].div(100)); // 1%
      expect(estimateRewards2[1]).to.be.closeTo(estimateRewards1[1], estimateRewards1[1].div(100)); // 1%
      expect(estimateRewards2[2]).to.be.closeTo(estimateRewards1[2], estimateRewards1[2].div(100)); // 1%
      expect(estimateRewards2[3]).to.be.closeTo(estimateRewards1[3], estimateRewards1[3].div(100)); // 1%
      expect(estimateRewards2[4]).to.be.closeTo(estimateRewards1[4], estimateRewards1[4].div(100)); // 7% slippage due to passing from c-power to deterministic
      expect(estimateRewards2[5]).to.be.closeTo(estimateRewards1[5], estimateRewards1[5].div(100)); // 5% affected by above
      expect(estimateRewards2[6]).to.be.closeTo(estimateRewards1[6], estimateRewards1[6].div(100)); // 1%
      expect(estimateRewards2[7]).to.be.closeTo(estimateRewards1[7], estimateRewards1[7].div(100)); // 5% affected by above
    });
    it('LP Pending rewards become zero if withdrawal all', async () => {
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
      expect(estimateRewards3[7]).to.be.eq(estimateRewards2[7]).to.be.eq(estimateRewards1[7]).to.be.eq(0); // after upgrade we pass from c-power to deterministic so it decreases a bit
      expect(estimateRewards2[0]).to.be.closeTo(estimateRewards1[0], estimateRewards1[0].div(100)); // 1%
      expect(estimateRewards2[1]).to.be.closeTo(estimateRewards1[1], estimateRewards1[1].div(100)); // 1%
      expect(estimateRewards2[2]).to.be.closeTo(estimateRewards1[2], estimateRewards1[2].div(100)); // 1%
      expect(estimateRewards2[3]).to.be.closeTo(estimateRewards1[3], estimateRewards1[3].div(100)); // 1%
      expect(estimateRewards2[4]).to.be.closeTo(estimateRewards1[4], estimateRewards1[4].div(100)); // 7% slippage due to passing from c-power to deterministic
      expect(estimateRewards2[5]).to.be.closeTo(estimateRewards1[5], estimateRewards1[5].div(100)); // 5% affected by above
      expect(estimateRewards2[6]).to.be.closeTo(estimateRewards1[6], estimateRewards1[6].div(100)); // 1%
      expect(estimateRewards2[7]).to.be.closeTo(estimateRewards1[7], estimateRewards1[7].div(100)); // 5% affected by above
    });
    it('Pending rewards become zero if a new user leaves right after depositing', async () => {});

    it('migrates RD into checkpoints and it does not affect rewards', async () => {
      console.log(gardens.length);
      console.log(gardens);
      for (const garden of gardens) {
        const gardenContract = await ethers.getContractAt('Garden', garden);
        console.log(`---------GARDEN ${garden} ${await gardenContract.name()}----------------`);
        const users = (await getUsers(garden)).map((u) => u.address);
        const strategies = await gardenContract.getFinalizedStrategies();
        // await increaseTime(ONE_DAY_IN_SECONDS * 100);
        const rewards = await distributor.getRewards(garden, await gardenContract.creator(), [...strategies]);
        console.log('BEFORE UPGRADE', await gardenContract.creator(), rewards.toString());
        /*  for (const user of users) {
          const rewards = await distributor.getRewards(garden, user, [...strategies]);
          console.log('BEFORE UPGRADE', user, rewards.toString());
        } */
      }
      // To test this we need to modifiy deploy.js script not updating distributor yet
      // So we can control before and after it is upgraded
      // We upgrade RD and re-check
      // upgrade rewards distributor
      const signers = await ethers.getSigners();
      const signer = signers[0];
      const distributorNewImpl = await deploy('RewardsDistributor', {
        from: signer.address,
      });
      const proxyAdmin = await ethers.getContractAt('ProxyAdmin', '0x0C085fd8bbFD78db0107bF17047E8fa906D871DC', owner);

      await proxyAdmin.upgrade(distributor.address, distributorNewImpl.address);

      for (const garden of gardens) {
        const gardenContract = await ethers.getContractAt('Garden', garden);
        console.log(`---------GARDEN ${garden} ${await gardenContract.name()}----------------`);
        const users = (await getUsers(garden)).map((u) => u.address);
        const strategies = await gardenContract.getFinalizedStrategies();
        // await increaseTime(ONE_DAY_IN_SECONDS * 100);
        const rewards = await distributor.getRewards(garden, await gardenContract.creator(), [...strategies]);
        console.log('AFTER UPGRADE', await gardenContract.creator(), rewards.toString());
        /*   for (const user of users) {
          const rewards = await distributor.getRewards(garden, user, [...strategies]);
          console.log('AFTER UPGRADE', user, rewards.toString());
        } */
      }
    });
    it('migrates RD into checkpoints and it does not affect unclaimed and pending rewards for previous members', async () => {
      /* const arkadGarden = '0xd42B3A30ca89155d6C3499c81F0C4e5A978bE5c2';
      const viewer = '0x3393bf9ff37899735b149fc2f5233b6639903dfa';
      const gardenContract = await ethers.getContractAt('Garden', arkadGarden);
      const creator = await gardenContract.creator();
      const viewerContract = await ethers.getContractAt('BabylonViewer', viewer);
      const strategies = await gardenContract.getFinalizedStrategies(); */
      const rewards = await distributor.getRewards(arkadGarden, await gardenContract.creator(), [...strategies]);
      const [, , estimateRewards] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      /*    const reserveContract = await getERC20(addresses.tokens.DAI);
      await reserveContract.connect(wallets[0]).approve(gardenContract.address, eth(9999999), { gasPrice: 0 });

      // New user deposit
      console.log('garden balance before', (await gardenContract.balanceOf(wallets[0].address)).toString());
      console.log('DAI balance before', (await reserveContract.balanceOf(wallets[0].address)).toString());

      await gardenContract.connect(wallets[0]).deposit(eth(2000), eth(1000), wallets[0].getAddress(), false, { gasPrice: 0 });
      console.log('garden balance after', (await gardenContract.balanceOf(wallets[0].address)).toString());
      console.log('DAI balance after', (await reserveContract.balanceOf(wallets[0].address)).toString());
 */
      // console.log('BEFORE UPGRADE', creator, rewards.toString());
      // console.log('BEFORE UPGRADE', estimateRewards.toString(), rewards.toString());
      // console.log('BEFORE UPGRADE', rewards.toString());
      console.log('-------UPGRADING RD--------');
      // upgrade rewards distributor
      /*    const signers = await ethers.getSigners();
      const signer = signers[0];
      const distributorNewImpl = await deploy('RewardsDistributor', {
        from: signer.address,
      });
      const proxyAdmin = await ethers.getContractAt('ProxyAdmin', '0x0C085fd8bbFD78db0107bF17047E8fa906D871DC', gnosis);
      await proxyAdmin.upgrade(distributor.address, distributorNewImpl.address);
       */
      await upgradeRD();

      const reserveContract = await getERC20(addresses.tokens.DAI);
      await reserveContract.connect(wallets[0]).approve(gardenContract.address, eth(9999999), { gasPrice: 0 });

      // New user deposit
      // console.log('garden balance before', (await gardenContract.balanceOf(wallets[0].address)).toString());
      // console.log('DAI balance before', (await reserveContract.balanceOf(wallets[0].address)).toString());

      // await gardenContract.connect(wallets[0]).deposit(eth(2000), eth(1000), wallets[0].getAddress(), false, { gasPrice: 0 });
      // console.log('garden balance after', (await gardenContract.balanceOf(wallets[0].address)).toString());
      // console.log('DAI balance after', (await reserveContract.balanceOf(wallets[0].address)).toString());

      // gardenContract = await ethers.getContractAt('Garden', arkadGarden);
      const rewards2 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      const [, , estimateRewards2] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      // console.log('AFTER UPGRADE', creator, rewards.toString());
      // console.log('AFTER UPGRADE', estimateRewards.toString(), rewards.toString());
      // console.log('AFTER UPGRADE ARKAD', rewards2.toString());
      // rewards = await distributor.getRewards(arkadGarden, wallets[0].address, [...strategies]);
      // [, , estimateRewards] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      console.log('AFTER UPGRADE (UNCLAIMED)', rewards2.toString());
      console.log('AFTER UPGRADE (PENDING)', estimateRewards2.toString());

      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewards3 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, creator);

      // const rewards3 = await distributor.getRewards(arkadGarden, wallets[0].address, [...strategies]);
      // const [, , estimateRewards3] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      console.log('AFTER INCREASE TIME (UNCLAIMED)', rewards3.toString());
      console.log('AFTER INCREASE TIME (PENDING)', estimateRewards3.toString());
      // Pending rewards
      expect(estimateRewards3[0]).to.be.gt(estimateRewards2[0]).to.be.gt(estimateRewards[0]);
      expect(estimateRewards3[2]).to.be.gt(estimateRewards2[2]).to.be.gt(estimateRewards[2]);
      expect(estimateRewards3[4]).to.be.gt(estimateRewards2[4]).to.be.gt(estimateRewards[4]);
      expect(estimateRewards3[5]).to.be.gt(estimateRewards2[5]).to.be.gt(estimateRewards[5]);
      expect(estimateRewards3[7]).to.be.gt(estimateRewards2[7]).to.be.gt(estimateRewards[7]);
      // unclaimed rewards deterministic
      expect(rewards3[0]).to.be.eq(rewards2[0]).to.be.eq(rewards[0]);
      expect(rewards3[1]).to.be.eq(rewards2[1]).to.be.eq(rewards[1]);
      expect(rewards3[2]).to.be.eq(rewards2[2]).to.be.eq(rewards[2]);
      expect(rewards3[3]).to.be.eq(rewards2[3]).to.be.eq(rewards[3]);
      expect(rewards3[6]).to.be.eq(rewards2[6]).to.be.eq(rewards[6]);
      // unclaimed rewards with slippage due to old contributor power not deterministic
      expect(rewards2[4]).to.be.closeTo(rewards[4], rewards[4].div(100));
      expect(rewards2[5]).to.be.closeTo(rewards[5], rewards[5].div(100));
      expect(rewards3[4]).to.be.closeTo(rewards2[4], rewards2[4].div(20)); // slippage due to contributor power not deterministic
      expect(rewards3[5]).to.be.closeTo(rewards2[5], rewards2[5].div(20)); // slippage due to contributor power not deterministic
      const creatorWallet = await impersonateAddress(creator);
      // New user deposit
      // console.log('garden balance before', (await gardenContract.balanceOf(creator)).toString());
      // console.log('DAI balance before', (await reserveContract.balanceOf(creator)).toString());
      console.log('---- new user deposit ----');
      // New deposit from Garden Creator
      await fund([creator], { tokens: [addresses.tokens.DAI] });
      await reserveContract.connect(creatorWallet).approve(arkadGarden, eth(9999999), { gasPrice: 0 });
      await gardenContract
        .connect(creatorWallet)
        .deposit(eth(2000), eth(1000), creatorWallet.getAddress(), false, { gasPrice: 0 });
      // console.log('garden balance after', (await gardenContract.balanceOf(creator)).toString());
      // console.log('DAI balance after', (await reserveContract.balanceOf(creator)).toString());
      const rewards4 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      const [, , estimateRewards4] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      // console.log('AFTER NEW DEPOSIT (UNCLAIMED)', rewards4.toString());
      // console.log('AFTER NEW DEPOSIT (PENDING)', estimateRewards4.toString());
      // unclaimed rewards deterministic
      expect(rewards4[0]).to.be.eq(rewards3[0]);
      expect(rewards4[1]).to.be.eq(rewards3[1]);
      expect(rewards4[2]).to.be.eq(rewards3[2]);
      expect(rewards4[3]).to.be.eq(rewards3[3]);
      expect(rewards4[6]).to.be.eq(rewards3[6]);
      console.log('LP', rewards4[4].toString());
      console.log('Total', rewards4[5].toString());
      console.log('estimateRewards', estimateRewards4[4].toString());

      await increaseTime(ONE_DAY_IN_SECONDS * 365);
      await increaseBlock(5);
      const rewards5 = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      const [, , estimateRewards5] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      console.log('LP 1year ahead', rewards5[4].toString());
      console.log('Total 1 year ahead', rewards5[5].toString());
      console.log('estimate 1 year ahead', estimateRewards5[4].toString());
    });
    it('migrates RD into checkpoints and it does not affect previous member rewards neither new users with checkpoints', async () => {
      const arkadGarden = '0xd42B3A30ca89155d6C3499c81F0C4e5A978bE5c2';
      const viewer = '0x3393bf9ff37899735b149fc2f5233b6639903dfa';
      const gardenContract = await ethers.getContractAt('Garden', arkadGarden);
      const creator = await gardenContract.creator();
      const viewerContract = await ethers.getContractAt('BabylonViewer', viewer);
      const strategies = await gardenContract.getFinalizedStrategies();
      let rewards = await distributor.getRewards(arkadGarden, await gardenContract.creator(), [...strategies]);
      let [, , estimateRewards] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      /*    const reserveContract = await getERC20(addresses.tokens.DAI);
      await reserveContract.connect(wallets[0]).approve(gardenContract.address, eth(9999999), { gasPrice: 0 });

      // New user deposit
      console.log('garden balance before', (await gardenContract.balanceOf(wallets[0].address)).toString());
      console.log('DAI balance before', (await reserveContract.balanceOf(wallets[0].address)).toString());

      await gardenContract.connect(wallets[0]).deposit(eth(2000), eth(1000), wallets[0].getAddress(), false, { gasPrice: 0 });
      console.log('garden balance after', (await gardenContract.balanceOf(wallets[0].address)).toString());
      console.log('DAI balance after', (await reserveContract.balanceOf(wallets[0].address)).toString());
 */
      // console.log('BEFORE UPGRADE', creator, rewards.toString());
      // console.log('BEFORE UPGRADE', estimateRewards.toString(), rewards.toString());
      console.log('BEFORE UPGRADE', rewards.toString());
      console.log('-------UPGRADING RD--------');
      // upgrade rewards distributor
      const signers = await ethers.getSigners();
      const signer = signers[0];
      const distributorNewImpl = await deploy('RewardsDistributor', {
        from: signer.address,
      });
      const proxyAdmin = await ethers.getContractAt('ProxyAdmin', '0x0C085fd8bbFD78db0107bF17047E8fa906D871DC', owner);
      await proxyAdmin.upgrade(distributor.address, distributorNewImpl.address);

      const reserveContract = await getERC20(addresses.tokens.DAI);
      await reserveContract.connect(wallets[0]).approve(gardenContract.address, eth(9999999), { gasPrice: 0 });

      // New user deposit
      console.log('garden balance before', (await gardenContract.balanceOf(wallets[0].address)).toString());
      console.log('DAI balance before', (await reserveContract.balanceOf(wallets[0].address)).toString());

      await gardenContract
        .connect(wallets[0])
        .deposit(eth(2000), eth(1000), wallets[0].getAddress(), false, { gasPrice: 0 });
      console.log('garden balance after', (await gardenContract.balanceOf(wallets[0].address)).toString());
      console.log('DAI balance after', (await reserveContract.balanceOf(wallets[0].address)).toString());

      // gardenContract = await ethers.getContractAt('Garden', arkadGarden);
      rewards = await distributor.getRewards(arkadGarden, creator, [...strategies]);
      [, , estimateRewards] = await viewerContract.getContributionAndRewards(arkadGarden, creator);
      // console.log('AFTER UPGRADE', creator, rewards.toString());
      // console.log('AFTER UPGRADE', estimateRewards.toString(), rewards.toString());
      console.log('AFTER UPGRADE ARKAD', rewards.toString());
      rewards = await distributor.getRewards(arkadGarden, wallets[0].address, [...strategies]);
      [, , estimateRewards] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      console.log('AFTER UPGRADE NEW USER (UNCLAIMED)', rewards.toString());
      console.log('AFTER UPGRADE NEW USER (PENDING)', estimateRewards.toString());

      await increaseTime(ONE_DAY_IN_SECONDS * 20);

      rewards = await distributor.getRewards(arkadGarden, wallets[0].address, [...strategies]);
      [, , estimateRewards] = await viewerContract.getContributionAndRewards(arkadGarden, wallets[0].address);
      console.log('AFTER INCREASE TIME NEW USER (UNCLAIMED)', rewards.toString());
      console.log('AFTER INCREASE TIME NEW USER (PENDING)', estimateRewards.toString());
    });
  });
});
