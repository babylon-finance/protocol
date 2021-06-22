const { expect } = require('chai');
// const { ethers } = require('hardhat');
const addresses = require('../lib/addresses');
const { setupTests } = require('./fixtures/GardenFixture');
const { GARDEN_PARAMS } = require('../lib/constants');

describe('Babylon Viewer', function () {
  let garden1;
  let signer1;
  let ishtarGate;
  let babController;
  let babViewer;

  beforeEach(async () => {
    ({
      babController,
      signer1,
      babViewer,
      garden1,
      ishtarGate,
    } = await setupTests()());
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babViewer.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe('can call getter methods', async function () {
    it('calls getGardenDetails', async function () {
      const gardenDetails = await babViewer.getGardenDetails(garden1.address);
      console.log('gardenDetails', gardenDetails);
      expect(gardenDetails[0]).to.equal(signer1.address); // Creator
      expect(gardenDetails[1]).to.equal(addresses.tokens.WETH); // Reserve Asset
      expect(gardenDetails[2][0]).to.equal(true); // Active
      expect(gardenDetails[2][1]).to.equal(true); // Private
      expect(gardenDetails[3].length).to.equal(1); // Active Strategies
      expect(gardenDetails[4].length).to.equal(0); // Finalized strategies
      const paramsCreation = gardenDetails[5];
      expect(paramsCreation[0]).to.equal(GARDEN_PARAMS[3]); // Hardlock
      expect(paramsCreation[1]).to.equal(0); // Withdrawals open until
      expect(paramsCreation[2]).to.equal(GARDEN_PARAMS[6]); // Min Votes Quorum
      expect(paramsCreation[3]).to.equal(100); // Max contributors
      expect(paramsCreation[4]).to.equal(GARDEN_PARAMS[0]); // Max deposit limit
      expect(paramsCreation[5]).to.equal(GARDEN_PARAMS[9]); // Min Voters
      expect(paramsCreation[6]).to.equal(GARDEN_PARAMS[7]); // Min Strategy Duration
      expect(paramsCreation[7]).to.equal(GARDEN_PARAMS[8]); // Max Strategy Duration
      expect(paramsCreation[8]).to.equal(GARDEN_PARAMS[5]); // Strategy cooldown
      expect(paramsCreation[9]).to.equal(GARDEN_PARAMS[4]); // Min contribution
      expect(paramsCreation[10]).to.equal(GARDEN_PARAMS[2]); // Min liquidity asset
      const status = gardenDetails[6];
      expect(status[0]).to.be.gt(0); // Principal
      expect(status[1]).to.equal(0); // Reserve rewards set aside
      expect(status[2]).to.equal(0); // Reserve asset principal window
      expect(status[3]).to.equal(0); // Absolute returns
      expect(status[4]).to.be.gt(0); // Initialized at
      expect(status[5]).to.equal(1); // Initialized at
      expect(status[6]).to.be.gt(0); // Stake
      expect(status[7]).to.be.gt(0); // Valuation
    });
  });
});
