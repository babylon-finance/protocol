const { expect } = require('chai');
const { ethers } = require('hardhat');

const {
  createStrategy,
  executeStrategy,
  finalizeStrategy,
  injectFakeProfits,
  deposit,
  getStrategy,
  DEFAULT_STRATEGY_PARAMS,
  GARDEN_PARAMS_STABLE,
} = require('../fixtures/StrategyHelper.js');
const { createGarden, transferFunds, depositFunds } = require('../fixtures/GardenHelper.js');

const { increaseTime } = require('../utils/test-helpers');
const { impersonateAddress } = require('../../lib/rpc');

const addresses = require('../../lib/addresses');
const { ONE_DAY_IN_SECONDS, ONE_ETH } = require('../../lib/constants.js');
const { setupTests } = require('../fixtures/GardenFixture');

describe('Get the Guap Garden Support Tests', function () {
  let babController;
  let owner;
  let keeper;
  let signer1;
  let garden1;
  let uniswapV3TradeIntegration;

  beforeEach(async () => {
    ({ owner, keeper, babController, signer1, garden1, uniswapV3TradeIntegration } = await setupTests()());
  });

  describe.only('Strategies support test', async function () {
    [{ token: addresses.tokens.RLY, name: 'RLY' }].forEach(({ token, name }) => {
      it(`should fail due to not enough liquidity a long strategy in ${name} asset from Get the guap garden`, async function () {
        const long1 = await getStrategy({
          kind: 'buy',
          state: 'vote',
          garden: garden1, // WETH Reserve Asset
          integration: uniswapV3TradeIntegration.address,
          specificParams: [token, 0],
        });
        console.log('EO');
        await expect(executeStrategy(long1, ONE_ETH)).to.be.revertedWith('Not enough liquidity');

        increaseTime(ONE_DAY_IN_SECONDS * 30);

        //await finalizeStrategy(long1);
      });
    });
  });
});
