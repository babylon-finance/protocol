const { expect } = require('chai');
const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');
const { DEFAULT_STRATEGY_PARAMS } = require('fixtures/StrategyHelper');
const { GARDEN_PARAMS, ADDRESS_ZERO } = require('lib/constants');
const { from, eth, parse } = require('lib/helpers');
const { increaseTime } = require('utils/test-helpers');

const { createGarden } = require('fixtures/GardenHelper');
const { getStrategy } = require('fixtures/StrategyHelper');
const { ONE_DAY_IN_SECONDS } = require('../../lib/constants');

describe('Babylon Viewer', function () {
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let uniswapV3TradeIntegration;
  let babViewer;
  let owner;
  let babController;

  beforeEach(async () => {
    ({
      uniswapV3TradeIntegration,
      signer1,
      signer2,
      signer3,
      babViewer,
      garden1,
      owner,
      babController,
    } = await setupTests()());
  });

  describe('can call getter methods', async function () {
    it('calls getGardenDetails', async function () {
      const gardenDetails = await babViewer.getGardenDetails(garden1.address);
      expect(gardenDetails[0]).to.equal('Absolute ETH Return [beta]'); // Name
      expect(gardenDetails[1]).to.equal('EYFA'); // Symbol
      expect(gardenDetails[2][0]).to.equal(signer1.address); // Creator
      expect(gardenDetails[3]).to.equal(addresses.tokens.WETH); // Reserve Asset
      expect(gardenDetails[4][0]).to.equal(true); // Active
      expect(gardenDetails[4][1]).to.equal(true); // Private
      expect(gardenDetails[5].length).to.equal(2); // Active Strategies Note: there are 2 not 1 in fixture for garden 1
      expect(gardenDetails[6].length).to.equal(0); // Finalized strategies
      const paramsCreation = gardenDetails[7];
      expect(paramsCreation[0]).to.equal(GARDEN_PARAMS[2]); // Hardlock
      expect(paramsCreation[1]).to.equal(GARDEN_PARAMS[5]); // Min Votes Quorum
      expect(paramsCreation[2]).to.equal(GARDEN_PARAMS[0]); // Max deposit limit
      expect(paramsCreation[3]).to.equal(GARDEN_PARAMS[8]); // Min Voters
      expect(paramsCreation[4]).to.equal(GARDEN_PARAMS[6]); // Min Strategy Duration
      expect(paramsCreation[5]).to.equal(GARDEN_PARAMS[7]); // Max Strategy Duration
      expect(paramsCreation[6]).to.equal(GARDEN_PARAMS[4]); // Strategy cooldown
      expect(paramsCreation[7]).to.equal(GARDEN_PARAMS[3]); // Min contribution
      expect(paramsCreation[8]).to.equal(GARDEN_PARAMS[1]); // Min liquidity asset
      expect(paramsCreation[9]).to.equal(0); // Keeper fees
      const status = gardenDetails[8];
      expect(status[0]).to.be.gt(0); // Principal
      expect(status[1]).to.equal(0); // Reserve rewards set aside
      expect(status[2]).to.equal(0); // Absolute returns
      expect(status[3]).to.be.gt(0); // Initialized at
      expect(status[4]).to.equal(1); // Total Contributors
      expect(status[5]).to.be.gt(0); // Stake
      expect(status[6]).to.be.gt(0); // Valuation
      expect(status[7]).to.be.gt(0); // totalSupply
      expect(status[8]).to.equal(0); // Seed
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
      const strategyOperations = await babViewer.getOperationsStrategy(gardenDetails[5][0]);
      expect(strategyOperations[0].length).to.equal(1);
      expect(strategyOperations[1].length).to.equal(1);
      expect(strategyOperations[2].length).to.equal(1);
      expect(strategyOperations[0][0]).to.equal(0);
      expect(strategyOperations[1][0]).to.equal(uniswapV3TradeIntegration.address);
      const decodedData = strategyOperations[2][0].slice(26, 64); // 64 bytes returned take the little endian ethereum address last 20 bytes of the 1st word ( 32 bytes)
      expect(decodedData.toLowerCase()).to.equal(addresses.tokens.DAI.slice(2, 40).toLowerCase()); // to match we need toLowerCase and remove 0x
    });

    it('calls get complete strategy', async function () {
      const gardenDetails = await babViewer.getGardenDetails(garden1.address);
      const strategyDetails = await babViewer.getCompleteStrategy(gardenDetails[5][0]);

      expect(strategyDetails[0]).to.equal(signer1.address); // Strategist

      expect(strategyDetails[1]).to.equal('Strategy Name'); // Name

      expect(strategyDetails[2][0]).to.equal(1); // Ops count
      expect(strategyDetails[2][1]).to.equal(DEFAULT_STRATEGY_PARAMS[1]); // Stake
      expect(strategyDetails[2][2]).to.equal(DEFAULT_STRATEGY_PARAMS[1]); // Positive votes
      expect(strategyDetails[2][3]).to.equal(0); // Negative votes
      expect(strategyDetails[2][4]).to.equal(0); // Capital Allocated
      expect(strategyDetails[2][5]).to.equal(0); // Capital Returned
      expect(strategyDetails[2][6]).to.equal(DEFAULT_STRATEGY_PARAMS[2]); // Duration
      expect(strategyDetails[2][7]).to.equal(DEFAULT_STRATEGY_PARAMS[3]); // Expected Return
      expect(strategyDetails[2][8]).to.equal(DEFAULT_STRATEGY_PARAMS[0]); // Max Capital Requested
      expect(strategyDetails[2][9]).to.be.gt(0); // Entered At
      expect(strategyDetails[2][10]).to.equal(0); // Get NAV
      expect(strategyDetails[2][11]).to.equal(0); // Rewards
      expect(strategyDetails[2][12]).to.equal(DEFAULT_STRATEGY_PARAMS[4]); // Max Allocation Percentage
      expect(strategyDetails[2][13]).to.equal(eth(0.05)); // maxAllocationPercentage
      expect(strategyDetails[2][14]).to.equal(0); // Strategy Rewards

      expect(strategyDetails[3][0]).to.equal(false); // Active
      expect(strategyDetails[3][1]).to.equal(true); // Data set
      expect(strategyDetails[3][2]).to.equal(false); // Finalized

      expect(strategyDetails[4][0]).to.equal(0); // Executed at
      expect(strategyDetails[4][1]).to.equal(0); // Exited At
      expect(strategyDetails[4][2]).to.equal(0); // Updated At
    });

    it('calls get contribution and rewards', async function () {
      const newGarden = await createGarden();
      await getStrategy({ state: 'active', garden: newGarden, specificParams: [addresses.tokens.USDC, 0] });
      const [, , pendingRewards] = await babViewer.getContributionAndRewards(newGarden.address, signer1.address);
      await increaseTime(ONE_DAY_IN_SECONDS);
      const [, , pendingRewards2] = await babViewer.getContributionAndRewards(newGarden.address, signer1.address);
      expect(pendingRewards[0]).to.equal(0); // Not profit strategy, strategist gets 0 BABL
      expect(pendingRewards[1]).to.equal(0); // Not profit strategy, strategist gets 0 profit
      expect(pendingRewards[2]).to.equal(0); // Not profit strategy, steward voting for gets 0 BABL
      expect(pendingRewards[3]).to.equal(0); // Not profit strategy, steward gets 0 profit
      expect(pendingRewards[4]).to.equal(0); // Just started, still 0
      expect(pendingRewards[5]).to.equal(0); // Just started, still 0
      expect(pendingRewards[6]).to.equal(0); // Just started, still 0
      expect(pendingRewards2[0]).to.equal(0); // Not profit strategy, strategist gets 0
      expect(pendingRewards2[1]).to.equal(0); // Not profit strategy, strategist gets 0 profit
      expect(pendingRewards2[2]).to.equal(0); // Not profit strategy, steward voting for gets 0
      expect(pendingRewards2[3]).to.equal(0); // Not profit strategy, steward gets 0 profit
      expect(pendingRewards2[4]).to.be.gt(0); // get BABL estimation for LP
      expect(pendingRewards2[5]).to.be.gt(0); // get total BABL estimation
      expect(pendingRewards2[6]).to.equal(0); // no profit strategy
    });

    it('calls get user gardens', async function () {
      const userGardens = await babViewer.getGardensUser(signer1.address, 0);
      const gardens = userGardens[0].filter((t) => t !== ADDRESS_ZERO);
      expect(gardens.length).to.be.gt(0);
      expect(userGardens[1].filter((t) => t).length).to.equal(gardens.length);
    });

    it('getPotentialVotes', async function () {
      const totalVotes = await babViewer.getPotentialVotes(garden1.address, [
        signer1.address,
        signer2.address,
        signer3.address,
      ]);

      expect(totalVotes).to.be.eq(eth());
    });
  });

  describe('getGardenPrincipal', async function () {
    it('for garden with no strategies', async function () {
      const principal = await babViewer.getGardenPrincipal(garden1.address);

      expect(principal).to.be.eq(eth());
    });

    it('for garden with active strategies', async function () {
      const garden = await createGarden();

      await getStrategy({ state: 'active', specificParams: [addresses.tokens.USDT, 0] });
      await getStrategy({ state: 'active', specificParams: [addresses.tokens.USDT, 0] });
      await getStrategy({ state: 'active', specificParams: [addresses.tokens.USDT, 0] });

      const principal = await babViewer.getGardenPrincipal(garden.address);

      expect(principal).to.be.eq(eth(13));
    });

    it('for garden with final strategies', async function () {
      const garden = await createGarden();

      await getStrategy({ state: 'final', specificParams: [addresses.tokens.USDT, 0] });
      await getStrategy({ state: 'final', specificParams: [addresses.tokens.USDT, 0] });
      await getStrategy({ state: 'final', specificParams: [addresses.tokens.USDT, 0] });

      const principal = await babViewer.getGardenPrincipal(garden.address);

      expect(principal).to.be.eq(eth(13));
    });
  });
});
