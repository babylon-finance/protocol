const { expect } = require('chai');
const { deployments } = require('hardhat');
const { deploy } = deployments;

const { from, parse, eth } = require('lib/helpers');
const { getUsers } = require('lib/web3');
const { getContracts, deployFixture } = require('lib/deploy');
const { increaseTime } = require('../utils/test-helpers');
const { ONE_DAY_IN_SECONDS } = require('../../lib/constants');

describe('migrate', function () {
  let owner;
  let gardens;
  let distributor;

  describe('after deployment', function () {
    beforeEach(async () => {
      ({ owner, gardens, distributor } = await deployFixture());
    });

    it('migrates RD into checkpoints and it does not affect rewards', async () => {
      console.log(gardens.length);
      console.log(gardens);
      for (const garden of gardens) {
        const gardenContract = await ethers.getContractAt('Garden', garden);
        console.log(`---------GARDEN ${garden} ${await gardenContract.name()}----------------`);
        const users = (await getUsers(garden)).map((u) => u.address);
        const strategies = await gardenContract.getFinalizedStrategies();
        await increaseTime(ONE_DAY_IN_SECONDS * 100);
        for (const user of users) {
          const rewards = await distributor.getRewards(garden, user, [...strategies]);
          console.log('BEFORE UPGRADE', user, rewards.toString());
        }
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
        await increaseTime(ONE_DAY_IN_SECONDS * 100);
        for (const user of users) {
          const rewards = await distributor.getRewards(garden, user, [...strategies]);
          console.log('AFTER UPGRADE', user, rewards.toString());
        }
      }
    });
  });
});
