const { expect } = require('chai');
const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');

describe('Heart Integration Test', function () {
  let heartGarden;
  let heart;
  let signer1;
  let signer2;
  let signer3;
  let garden1;
  let garden2;
  let garden3;
  let keeper;
  let owner;
  let babController;

  beforeEach(async () => {
    ({
      heartGarden,
      heart,
      signer1,
      signer2,
      signer3,
      garden1,
      garden2,
      garden3,
      owner,
      keeper,
      babController,
    } = await setupTests()());
  });

  describe('pump', async function () {
    it('will revert if already pumped', async function () {});
    it('will revert if garden votes have not been set', async function () {});
    it('will revert if fees are not enough to pump', async function () {});
    it('will pump correctly with 3 ETH', async function () {});
    it('will pump correctly with 3 ETH, 1000 DAI', async function () {});
    it('will pump correctly with 3 ETH, 1000 DAI, 1000 USDC', async function () {});
  });
});
