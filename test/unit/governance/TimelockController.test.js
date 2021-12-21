const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ONE_DAY_IN_SECONDS } = require('lib/constants');
const { increaseTime } = require('utils/test-helpers');

const { setupTests } = require('fixtures/GardenFixture');

describe.skip('TimelockController', function () {
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let bablToken;
  let babGovernor;
  let timelockController;

  beforeEach(async () => {
    ({ owner, signer1, signer2, signer3, bablToken, babGovernor, timelockController } = await setupTests()());
  });
  describe('Deployment check', function () {
    it('should successfully deploy TimelockController contract', async function () {
      const deployedc = await timelockController.deployed();
      expect(!!deployedc).to.equal(true);
      expect(await timelockController.getMinDelay()).to.be.equal(ONE_DAY_IN_SECONDS);
    });
  });

  describe('scheduleBatch', function () {});

  describe('cancel', function () {});

  describe('execute', function () {});

  describe('executeBatch', function () {});
});
