const { expect } = require('chai');

const { from, parse, eth } = require('lib/helpers');
const { getUsers } = require('lib/web3');
const { getContracts, deployFixture } = require('lib/deploy');

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
        for (const strategy of strategies) {
          const strategyContract = await ethers.getContractAt('Strategy', strategy);
          const rewards = await strategyContract.strategyRewards();
          const strategist = await strategyContract.strategist();
          if (rewards > 0) {
            console.log(`-------------STRATEGY GOT REWARDS ${strategy}------------`, rewards.toString());
            for (const user of users) {
              const rewards = await distributor.getRewards(garden, user, [strategy]);
              const isStrategist = strategist.toLowerCase() === user.toLowerCase;
              console.log('strategist - user', strategist, user);
              console.log('USER', user, rewards.toString(), isStrategist);
              // expect(rewards).to.eql([true, true]);
            }
          }
        }
      }
    });
  });
});
