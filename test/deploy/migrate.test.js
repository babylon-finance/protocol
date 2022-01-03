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
  let affectedGarden;
  let gardenMember2;
  let strategist;

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
        affectedGarden,
        gardenMember2,
        strategist,
      } = await deployFixture());

      // await increaseTime(1000);

      wallets = await createWallets(1, {
        tokens: [addresses.tokens.DAI, addresses.tokens.ETH],
        amounts: [eth(10000), eth(900)],
      });
      // console.log(wallets[0].address);
      await ishtarGate.connect(owner).setCreatorPermissions(wallets[0].address, true, { gasPrice: 0 });

      arkadGarden = '0xd42B3A30ca89155d6C3499c81F0C4e5A978bE5c2';
      affectedGarden = '0x8e6DAfCACE886235E2c5E93d72D85230B449926d';
      const viewer = '0x3393bf9ff37899735b149fc2f5233b6639903dfa';
      gardenContract = await ethers.getContractAt('Garden', affectedGarden);
      creator = await gardenContract.creator();
      gardenMember = await impersonateAddress('0x80e82A9fd9B1D3886d4042e5f06CA1cC753d3DdB');
      gardenMember2 = await impersonateAddress('0x4ecbaa7d2f86f2d78c04f49986ec2c57938752a6'); // depositor
      strategist = await impersonateAddress('0x15ff054550a89b5f38570c0884ad8a7b8f8527ba');
      viewerContract = await ethers.getContractAt('BabylonViewer', viewer);
      strategies = await gardenContract.getFinalizedStrategies();
      creatorWallet = await impersonateAddress(creator);
      const reserveContract = await getERC20(addresses.tokens.DAI);
      await fund([creator, wallets[0].address, gardenMember.address, gardenMember2.address], {
        tokens: [addresses.tokens.DAI],
        amounts: eth(400000),
      });
      await reserveContract.connect(creatorWallet).approve(arkadGarden, eth(9999999), { gasPrice: 0 });
      await reserveContract.connect(wallets[0]).approve(gardenContract.address, eth(9999999), { gasPrice: 0 });
      await reserveContract.connect(gardenMember).approve(gardenContract.address, eth(9999999), { gasPrice: 0 });
      await reserveContract.connect(gardenMember2).approve(gardenContract.address, eth(9999999), { gasPrice: 0 });

      // await increaseBlock(1);
    });

    it('reproduce issue on babl and fixed income', async () => {
      const rewardsUser1Snapshot1 = await distributor.getRewards(affectedGarden, gardenMember.address, [...strategies]);
      const rewardsUser2Snapshot1 = await distributor.getRewards(affectedGarden, gardenMember2.address, [
        ...strategies,
      ]);
      const [, , estimateUser1Rewards1] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember.address,
      );
      const [, , estimateUser2Rewards1] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember2.address,
      );

      await upgradeRD();
      console.log('RD upgraded !');
      const rewardsUser1Snapshot2 = await distributor.getRewards(affectedGarden, gardenMember.address, [...strategies]);
      const rewardsUser2Snapshot2 = await distributor.getRewards(affectedGarden, gardenMember2.address, [
        ...strategies,
      ]);
      const [, , estimateUser1Rewards2] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember.address,
      );
      const [, , estimateUser2Rewards2] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember2.address,
      );

      await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewardsUser1Snapshot3 = await distributor.getRewards(affectedGarden, gardenMember.address, [...strategies]);
      const rewardsUser2Snapshot3 = await distributor.getRewards(affectedGarden, gardenMember2.address, [
        ...strategies,
      ]);
      const [, , estimateUser1Rewards3] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember.address,
      );
      const [, , estimateUser2Rewards3] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember2.address,
      );

      console.log('Unclaimed rewards user A 1', rewardsUser1Snapshot1.toString());
      console.log('Unclaimed rewards user A 2', rewardsUser1Snapshot2.toString());
      console.log('Unclaimed rewards user A 3', rewardsUser1Snapshot3.toString());
      console.log('Estimate rewards user A 1', estimateUser1Rewards1.toString());
      console.log('Estimate rewards user A 2', estimateUser1Rewards2.toString());
      console.log('Estimate rewards user A 3', estimateUser1Rewards3.toString());

      console.log('Unclaimed rewards user B 1', rewardsUser2Snapshot1.toString());
      console.log('Unclaimed rewards user B 2', rewardsUser2Snapshot2.toString());
      console.log('Unclaimed rewards user B 3', rewardsUser2Snapshot3.toString());
      console.log('Estimate rewards user B 1', estimateUser2Rewards1.toString());
      console.log('Estimate rewards user B 2', estimateUser2Rewards2.toString());
      console.log('Estimate rewards user B 3', estimateUser2Rewards3.toString());
    });
    it('reproduce issue with BIG deposit on babl and fixed income', async () => {
      const rewardsUser1Snapshot1 = await distributor.getRewards(affectedGarden, gardenMember.address, [...strategies]);
      const rewardsUser2Snapshot1 = await distributor.getRewards(affectedGarden, gardenMember2.address, [
        ...strategies,
      ]);
      const rewardsUser3Snapshot1 = await distributor.getRewards(affectedGarden, strategist.address, [...strategies]);
      const [, , estimateUser1Rewards1] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember.address,
      );
      const [, , estimateUser2Rewards1] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember2.address,
      );
      const [, , estimateUser3Rewards1] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        strategist.address,
      );

      await upgradeRD();
      console.log('RD upgraded !');
      console.log('New big deposit');
      console.log('REAL SUPPLY BEFORE', (await gardenContract.totalSupply()).toString());
      await gardenContract
        .connect(gardenMember2)
        .deposit(eth(298519.4827302369), eth(1000), gardenMember2.address, false, { gasPrice: 0 });
      /* await gardenContract
        .connect(gardenMember2)
        .deposit(eth(16538.3142), eth(1000), gardenMember2.address, false, { gasPrice: 0 }); */
      await increaseTime(1);
      const rewardsUser1Snapshot2 = await distributor.getRewards(affectedGarden, gardenMember.address, [...strategies]);
      const rewardsUser2Snapshot2 = await distributor.getRewards(affectedGarden, gardenMember2.address, [
        ...strategies,
      ]);
      const rewardsUser3Snapshot2 = await distributor.getRewards(affectedGarden, strategist.address, [...strategies]);
      const [, , estimateUser1Rewards2] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember.address,
      );
      const [, , estimateUser2Rewards2] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember2.address,
      );
      const [, , estimateUser3Rewards2] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        strategist.address,
      );
      await increaseTime(256855); // fix (withdraw)
      console.log('user balance before withdraw', (await gardenContract.balanceOf(gardenMember2.address)).toString());
      console.log('New big withdrawal in course... ');
      await gardenContract
        .connect(gardenMember2)
        .withdraw(eth(344099.603063301640070475), 1, gardenMember2.address, false, ADDRESS_ZERO, { gasPrice: 0 });

      /* await gardenContract
        .connect(gardenMember2)
        .withdraw(eth(442658.425754178), 1, gardenMember2.address, false, ADDRESS_ZERO, { gasPrice: 0 }); */
      console.log('user balance after withdraw', (await gardenContract.balanceOf(gardenMember2.address)).toString());
      await increaseTime(1);
      console.log('REAL SUPPLY AFTER', (await gardenContract.totalSupply()).toString());
      await increaseTime(1);
      // await distributor.connect(owner).syncPower(affectedGarden, gardenMember2.address, eth(4305.068937746358846003), eth(113700363995.639), await gardenContract.balanceOf(gardenMember2.address) , false);
      await distributor
        .connect(owner)
        .syncPower(
          affectedGarden,
          gardenMember2.address,
          eth(4305.068937746358846003),
          eth(93064648196.3871),
          await gardenContract.balanceOf(gardenMember2.address),
          false,
        );

      /*  FIX:
     syncPower(
        address _garden,
        address _contributor,
        uint256 _newGardenAvgBalance,
        uint256 _newGardenPower,
        uint256 _newUserAvgBalance,
        uint256 _newUserPower
        bool _addOrSubstract */
      // await increaseTime(ONE_DAY_IN_SECONDS * 20);
      const rewardsUser1Snapshot3 = await distributor.getRewards(affectedGarden, gardenMember.address, [...strategies]);
      const rewardsUser2Snapshot3 = await distributor.getRewards(affectedGarden, gardenMember2.address, [
        ...strategies,
      ]);
      const rewardsUser3Snapshot3 = await distributor.getRewards(affectedGarden, strategist.address, [...strategies]);
      const [, , estimateUser1Rewards3] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember.address,
      );
      const [, , estimateUser2Rewards3] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember2.address,
      );
      const [, , estimateUser3Rewards3] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        strategist.address,
      );

      console.log('Unclaimed rewards user A 1', rewardsUser1Snapshot1.toString());
      console.log('Unclaimed rewards user A 2', rewardsUser1Snapshot2.toString());
      console.log('Unclaimed rewards user A 3', rewardsUser1Snapshot3.toString());
      console.log('Estimate rewards user A 1', estimateUser1Rewards1.toString());
      console.log('Estimate rewards user A 2', estimateUser1Rewards2.toString());
      console.log('Estimate rewards user A 3', estimateUser1Rewards3.toString());

      console.log('Unclaimed rewards user B 1', rewardsUser2Snapshot1.toString());
      console.log('Unclaimed rewards user B 2', rewardsUser2Snapshot2.toString());
      console.log('Unclaimed rewards user B 3', rewardsUser2Snapshot3.toString());
      console.log('Estimate rewards user B 1', estimateUser2Rewards1.toString());
      console.log('Estimate rewards user B 2', estimateUser2Rewards2.toString());
      console.log('Estimate rewards user B 3', estimateUser2Rewards3.toString());

      console.log('Unclaimed rewards user C 1', rewardsUser3Snapshot1.toString());
      console.log('Unclaimed rewards user C 2', rewardsUser3Snapshot2.toString());
      console.log('Unclaimed rewards user C 3', rewardsUser3Snapshot3.toString());
      console.log('Estimate rewards user C 1', estimateUser3Rewards1.toString());
      console.log('Estimate rewards user C 2', estimateUser3Rewards2.toString());
      console.log('Estimate rewards user C 3', estimateUser3Rewards3.toString());
    });
    it('FIX issue with BIG deposit on babl and fixed income', async () => {
      const rewardsUser1Snapshot1 = await distributor.getRewards(affectedGarden, gardenMember.address, [...strategies]);
      const rewardsUser2Snapshot1 = await distributor.getRewards(affectedGarden, gardenMember2.address, [
        ...strategies,
      ]);
      const rewardsUser3Snapshot1 = await distributor.getRewards(affectedGarden, strategist.address, [...strategies]);
      const [, , estimateUser1Rewards1] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember.address,
      );
      const [, , estimateUser2Rewards1] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember2.address,
      );
      const [, , estimateUser3Rewards1] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        strategist.address,
      );

      await upgradeRD();
      console.log('RD upgraded !');
      await increaseTime(1);
      const rewardsUser1Snapshot2 = await distributor.getRewards(affectedGarden, gardenMember.address, [...strategies]);
      const rewardsUser2Snapshot2 = await distributor.getRewards(affectedGarden, gardenMember2.address, [
        ...strategies,
      ]);
      const rewardsUser3Snapshot2 = await distributor.getRewards(affectedGarden, strategist.address, [...strategies]);
      const [, , estimateUser1Rewards2] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember.address,
      );
      const [, , estimateUser2Rewards2] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember2.address,
      );
      const [, , estimateUser3Rewards2] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        strategist.address,
      );
      console.log('Fixing rewards....');
      await distributor
        .connect(gnosis)
        .syncPower(
          affectedGarden,
          gardenMember2.address,
          eth(4305.068937746358846003),
          eth(93064648196.3871),
          await gardenContract.balanceOf(gardenMember2.address),
          false,
        );

      const rewardsUser1Snapshot3 = await distributor.getRewards(affectedGarden, gardenMember.address, [...strategies]);
      const rewardsUser2Snapshot3 = await distributor.getRewards(affectedGarden, gardenMember2.address, [
        ...strategies,
      ]);
      const rewardsUser3Snapshot3 = await distributor.getRewards(affectedGarden, strategist.address, [...strategies]);
      const [, , estimateUser1Rewards3] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember.address,
      );
      const [, , estimateUser2Rewards3] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        gardenMember2.address,
      );
      const [, , estimateUser3Rewards3] = await viewerContract.getContributionAndRewards(
        affectedGarden,
        strategist.address,
      );

      console.log('Unclaimed rewards user A 1', rewardsUser1Snapshot1.toString());
      console.log('Unclaimed rewards user A 2', rewardsUser1Snapshot2.toString());
      console.log('Unclaimed rewards user A 3', rewardsUser1Snapshot3.toString());
      console.log('Estimate rewards user A 1', estimateUser1Rewards1.toString());
      console.log('Estimate rewards user A 2', estimateUser1Rewards2.toString());
      console.log('Estimate rewards user A 3', estimateUser1Rewards3.toString());

      console.log('Unclaimed rewards user B 1', rewardsUser2Snapshot1.toString());
      console.log('Unclaimed rewards user B 2', rewardsUser2Snapshot2.toString());
      console.log('Unclaimed rewards user B 3', rewardsUser2Snapshot3.toString());
      console.log('Estimate rewards user B 1', estimateUser2Rewards1.toString());
      console.log('Estimate rewards user B 2', estimateUser2Rewards2.toString());
      console.log('Estimate rewards user B 3', estimateUser2Rewards3.toString());

      console.log('Unclaimed rewards user C 1', rewardsUser3Snapshot1.toString());
      console.log('Unclaimed rewards user C 2', rewardsUser3Snapshot2.toString());
      console.log('Unclaimed rewards user C 3', rewardsUser3Snapshot3.toString());
      console.log('Estimate rewards user C 1', estimateUser3Rewards1.toString());
      console.log('Estimate rewards user C 2', estimateUser3Rewards2.toString());
      console.log('Estimate rewards user C 3', estimateUser3Rewards3.toString());
    });
    it.only('All garden fix at once', async () => {
      await upgradeRD();
      const users = (await getUsers(affectedGarden)).map((u) => u.address);
      const strategies = await gardenContract.getFinalizedStrategies();
      let BABL = from(0);
      let fixBABL = from(0);
      for (const user of users) {
        const rewards = await distributor.getRewards(affectedGarden, user, [...strategies]);
        console.log('BEFORE FIX', user, rewards.toString());
        BABL = BABL.add(from(rewards[5]));
      }
      console.log('Fixing rewards....', BABL.toString());
      // console.log((await viewerContract.getContributionAndRewards(affectedGarden, gardenMember2.address)).toString());

      // await distributor.connect(gnosis).syncPower(affectedGarden, gardenMember2.address, eth(4305.068937746358846003), eth(93064648196.387100), await gardenContract.balanceOf(gardenMember2.address) , false);
      await distributor
        .connect(owner)
        .syncPower(
          affectedGarden,
          gardenMember2.address,
          eth(4305.068937746358846003),
          eth(88383703544.82434),
          await gardenContract.balanceOf(gardenMember2.address),
          false,
        );
      // console.log((await viewerContract.getContributionAndRewards(affectedGarden, gardenMember2.address)).toString());

      await increaseTime(1);
      for (const user of users) {
        const rewards = await distributor.getRewards(affectedGarden, user, [...strategies]);
        console.log('AFTER FIX', user, rewards.toString());
        fixBABL = fixBABL.add(from(rewards[5]));
      }
      console.log('Fixed rewards....', fixBABL.toString());
    });
  });
});
