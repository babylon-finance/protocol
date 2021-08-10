const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ONE_ETH, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { increaseTime } = require('utils/test-helpers');

const { setupTests } = require('fixtures/GardenFixture');

describe('TimelockController contract', function () {
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let bablToken;
  let governorBabylon;
  let timelockController;

  beforeEach(async () => {
    ({ owner, signer1, signer2, signer3, bablToken, governorBabylon, timelockController } = await setupTests()());
  });
  describe('Deployment check', function () {
    it('should successfully deploy TimelockController contract', async function () {
      const deployedc = await timelockController.deployed();
      expect(!!deployedc).to.equal(true);
    });
  });
});
