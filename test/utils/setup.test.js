const { expect } = require('chai');

const { increaseTime, increaseBlock, getTimestamp, mineInBlock } = require('utils/test-helpers');
const { setup } = require('lib/scripts/setup');
const { setupTests } = require('fixtures/GardenFixture');

describe('setup', function () {
  beforeEach(async () => {
    await setupTests()();
  });

  it('runs', async function () {
    const hre = require('hardhat');
    await setup(hre);
  });
});
