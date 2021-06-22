const { expect } = require('chai');
// const { ethers } = require('hardhat');
const addresses = require('../lib/addresses');
const { setupTests } = require('./fixtures/GardenFixture');
const { DEFAULT_STRATEGY_PARAMS } = require('./fixtures/StrategyHelper');
const { GARDEN_PARAMS, ADDRESS_ZERO } = require('../lib/constants');

describe('Babylon Viewer', function () {
  let garden1;
  let signer1;
  let kyberTradeIntegration;
  let babViewer;

  beforeEach(async () => {
    ({ kyberTradeIntegration, signer1, babViewer, garden1 } = await setupTests()());
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
      expect(gardenDetails[0]).to.equal(''); // Name
      expect(gardenDetails[1]).to.equal(''); // Symbol
      expect(gardenDetails[2]).to.equal(signer1.address); // Creator
      expect(gardenDetails[3]).to.equal(addresses.tokens.WETH); // Reserve Asset
      expect(gardenDetails[4][0]).to.equal(true); // Active
      expect(gardenDetails[4][1]).to.equal(true); // Private
      expect(gardenDetails[5].length).to.equal(1); // Active Strategies
      expect(gardenDetails[6].length).to.equal(0); // Finalized strategies
      const paramsCreation = gardenDetails[7];
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
      const status = gardenDetails[8];
      expect(status[0]).to.be.gt(0); // Principal
      expect(status[1]).to.equal(0); // Reserve rewards set aside
      expect(status[2]).to.equal(0); // Reserve asset principal window
      expect(status[3]).to.equal(0); // Absolute returns
      expect(status[4]).to.be.gt(0); // Initialized at
      expect(status[5]).to.equal(1); // Initialized at
      expect(status[6]).to.be.gt(0); // Stake
      expect(status[7]).to.be.gt(0); // Valuation
    });

    it('calls get permissions', async function () {
      const globalPermissions = await babViewer.getPermissions(signer1.address);
      expect(globalPermissions[0]).to.equal(true);
      expect(globalPermissions[1]).to.equal(true);
    });

    it('calls get garden permissions', async function () {
      const gardenPermissions = await babViewer.getGardenPermissions(garden1.address, signer1.address);
      expect(gardenPermissions[0]).to.equal(true);
      expect(gardenPermissions[1]).to.equal(true);
      expect(gardenPermissions[2]).to.equal(true);
    });

    it('calls get operations strategy', async function () {
      const gardenDetails = await babViewer.getGardenDetails(garden1.address);
      const strategyOperations = await babViewer.getOperationsStrategy(gardenDetails[3][0]);
      expect(strategyOperations[0].length).to.equal(1);
      expect(strategyOperations[1].length).to.equal(1);
      expect(strategyOperations[2].length).to.equal(1);
      expect(strategyOperations[0][0]).to.equal(0);
      expect(strategyOperations[1][0]).to.equal(kyberTradeIntegration.address);
      expect(strategyOperations[2][0]).to.equal(addresses.tokens.DAI);
    });

    it('calls get complete strategy', async function () {
      const gardenDetails = await babViewer.getGardenDetails(garden1.address);
      const strategyDetails = await babViewer.getCompleteStrategy(gardenDetails[3][0]);
      expect(strategyDetails[0]).to.equal(signer1.address); // Strategist
      expect(strategyDetails[1][0]).to.equal(1); // Ops count
      expect(strategyDetails[1][1]).to.equal(DEFAULT_STRATEGY_PARAMS[1]); // Stake
      expect(strategyDetails[1][2]).to.equal(DEFAULT_STRATEGY_PARAMS[1]); // Positive votes
      expect(strategyDetails[1][3]).to.equal(0); // Negative votes
      expect(strategyDetails[1][4]).to.equal(0); // Capital Allocated
      expect(strategyDetails[1][5]).to.equal(0); // Capital Returned
      expect(strategyDetails[1][6]).to.equal(DEFAULT_STRATEGY_PARAMS[2]); // Duration
      expect(strategyDetails[1][7]).to.equal(DEFAULT_STRATEGY_PARAMS[3]); // Expected Return
      expect(strategyDetails[1][8]).to.equal(DEFAULT_STRATEGY_PARAMS[0]); // Max Capital Requested
      expect(strategyDetails[1][9]).to.be.gt(0); // Entered At
      expect(strategyDetails[1][10]).to.equal(0); // Get NAV
      expect(strategyDetails[2][0]).to.equal(false); // Active
      expect(strategyDetails[2][1]).to.equal(true); // Data set
      expect(strategyDetails[2][2]).to.equal(false); // Finalized
      expect(strategyDetails[3][0]).to.equal(0); // Executed at
      expect(strategyDetails[3][1]).to.equal(0); // Exited At
      expect(strategyDetails[3][2]).to.equal(0); // Updated At
    });

    it('calls get user gardens', async function () {
      const userGardens = await babViewer.getGardensUser(signer1.address, 0);
      const gardens = userGardens[0].filter((t) => t !== ADDRESS_ZERO);
      expect(gardens.length).to.be.gt(0);
      expect(userGardens[1].filter((t) => t).length).to.equal(gardens.length);
    });
  });
});
