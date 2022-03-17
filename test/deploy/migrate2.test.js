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

  /* async function upgradeRD() {
    const signers = await ethers.getSigners();
    const signer = signers[0];
    const distributorNewImpl = await deploy('RewardsDistributor', {
      from: signer.address,
    });
    const proxyAdmin = await ethers.getContractAt('ProxyAdmin', '0x0C085fd8bbFD78db0107bF17047E8fa906D871DC', gnosis);
    await proxyAdmin.upgrade(distributor.address, distributorNewImpl.address); 
  }*/

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
      gardenContract = await ethers.getContractAt('IGarden', affectedGarden);
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

    it('All garden fix at once', async () => {
      await upgradeRD();
      const users = (await getUsers(affectedGarden)).map((u) => u.address);
      const strategies = await gardenContract.getFinalizedStrategies();
      let BABL = from(0);
      let estimateBABL = from(0);
      let fixBABL = from(0);
      let fixEstimateBABL = from(0);
      for (const user of users) {
        const rewards = await distributor.getRewards(affectedGarden, user, [...strategies]);
        const [, , estimateRewards] = await viewerContract.getContributionAndRewards(affectedGarden, user);
        console.log('BEFORE FIX UNCLAIMED', user, rewards.toString());
        console.log('BEFORE FIX ESTIMATED', user, estimateRewards.toString());
        BABL = BABL.add(from(rewards[5]));
        estimateBABL = estimateBABL.add(from(estimateRewards[5]));
      }
      console.log('Rewards....', BABL.toString());
      console.log('Estimate rewards....', estimateBABL.toString());
      await distributor.connect(gnosis).migrateGardenToCheckpoints(affectedGarden, true);
      await increaseTime(1);
      for (const user of users) {
        const rewards = await distributor.getRewards(affectedGarden, user, [...strategies]);
        const [, , estimateRewards] = await viewerContract.getContributionAndRewards(affectedGarden, user);
        console.log('AFTER FIX UNCLAIMED', user, rewards.toString());
        console.log('AFTER FIX ESTIMATED', user, estimateRewards.toString());
        fixBABL = fixBABL.add(from(rewards[5]));
        fixEstimateBABL = fixEstimateBABL.add(from(estimateRewards[5]));
      }
      console.log('Fixed rewards....', fixBABL.toString());
      console.log('Fixed estimate rewards....', fixEstimateBABL.toString());
    });
    it.only('user rewards support', async () => {
      const garden = '0xB5bD20248cfe9480487CC0de0d72D0e19eE0AcB6';
      const users = ['0x2c59900B9442b7A865F93219c04f553a0D7BD003'];
      // const strategies = ['0x4f85dD417d19058cA81564f41572fb90D2F7e935','0x07DEbD22bCa7d010E53fc8ec23E8ADc3a516eC08', '0x6b9398A256E78616C4C8DceE52B8AA0F0518E268','0xbf2647e5319cFbbE840ad0fafbE5E073E89B40f0', '0xd24A10741E6A0e7b48669629722fF194Bfa472Bb'];
      const strategies = ['0x4f85dD417d19058cA81564f41572fb90D2F7e935', '0x07DEbD22bCa7d010E53fc8ec23E8ADc3a516eC08'];
      // const users = (await getUsers(affectedGarden)).map((u) => u.address);
      // const strategies = await gardenContract.getFinalizedStrategies();
      let BABL = from(0);
      let estimateBABL = from(0);
      let fixBABL = from(0);
      let fixEstimateBABL = from(0);
      for (const user of users) {
        const rewards = await distributor.getRewards(garden, user, [...strategies]);
        const [, , estimateRewards] = await viewerContract.getContributionAndRewards(garden, user);
        console.log('BEFORE FIX UNCLAIMED', user, rewards.toString());
        console.log('BEFORE FIX ESTIMATED', user, estimateRewards.toString());
        BABL = BABL.add(from(rewards[5]));
        estimateBABL = estimateBABL.add(from(estimateRewards[5]));
      }
      console.log('Rewards....', BABL.toString());
      console.log('Estimate rewards....', estimateBABL.toString());

      /* for (let i = 0; i < 20; i++) {
        console.log('user rewards %i', i, (await distributor.getRewards(garden, users[0], [...strategies])).toString())
        await increaseTime(ONE_DAY_IN_SECONDS * 5);
      } */
      await distributor.connect(gnosis).migrateAddressToCheckpoints(users, true);
      await increaseTime(1);
      for (const user of users) {
        const rewards = await distributor.getRewards(garden, user, [...strategies]);
        const [, , estimateRewards] = await viewerContract.getContributionAndRewards(garden, user);
        console.log('AFTER FIX UNCLAIMED', user, rewards.toString());
        console.log('AFTER FIX ESTIMATED', user, estimateRewards.toString());
        fixBABL = fixBABL.add(from(rewards[5]));
        fixEstimateBABL = fixEstimateBABL.add(from(estimateRewards[5]));
      }
      console.log('Fixed rewards....', fixBABL.toString());
      console.log('Fixed estimate rewards....', fixEstimateBABL.toString());
    });
  });
});
