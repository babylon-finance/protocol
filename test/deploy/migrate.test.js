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

    it('migrates all users for all gardens', async () => {
      for (const garden of gardens) {
        const users = (await getUsers(garden)).map((u) => u.address);

        await distributor.connect(owner).migrateBetaUsers(garden, users);
        for (const user of users) {
          const [, beta] = await distributor.getBetaMigration(garden, user);
          expect(beta).to.eql([true, true]);
        }
      }
    });
  });
});
