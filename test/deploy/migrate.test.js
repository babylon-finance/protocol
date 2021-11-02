const { expect } = require('chai');

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
          console.log(user, rewards.toString());
        }
      }
    });
  });
});
