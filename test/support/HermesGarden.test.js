const { expect } = require('chai');
const chaiAsPromised = require('chai-as-promised');
const { ethers } = require('hardhat');

require('chai').use(chaiAsPromised);

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

describe('Hermes Garden Support Tests', function () {
  let babController;
  let owner;
  let keeper;
  let signer1;
  let signer2;
  let signer3;
  let garden1;
  let garden2;
  let daiGarden;
  let strategy11;
  let strategy21;
  let wethToken;
  let treasury;
  let aaveLendIntegration;
  let uniswapV3TradeIntegration;
  let uniswapPoolIntegration;
  let balancerIntegration;
  let oneInchPoolIntegration;
  let yearnVaultIntegration;

  beforeEach(async () => {
    ({
      owner,
      keeper,
      babController,
      signer1,
      garden1,
      garden2,
      daiGarden,
      treasury,
      strategy11,
      strategy21,
      signer2,
      signer3,
      aaveLendIntegration,
      uniswapV3TradeIntegration,
      uniswapPoolIntegration,
      balancerIntegration,
      oneInchPoolIntegration,
      yearnVaultIntegration,
    } = await setupTests()());

    strategyDataset = await ethers.getContractAt('Strategy', strategy11);
    strategyCandidate = await ethers.getContractAt('Strategy', strategy21);

    wethToken = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Strategies support test', async function () {
    it.only('should correctly execute a long strategy in PILOT asset on 20210731 from Hermes garden', async function () {
      let token = addresses.tokens.DAI;
      await transferFunds(token);
      const garden = await createGarden({ reserveAsset: token });
      const gardenReserveAsset = await ethers.getContractAt('IERC20', token);
      await depositFunds(token, garden);

      let asset = '0x37c997b35c619c21323f3518b9357914e8b99525'; // PILOT

      const long1 = await getStrategy({
        kind: 'buy',
        state: 'vote',
        garden: garden1,
        integration: uniswapV3TradeIntegration.address,
        specificParams: [asset, 0],
      });

      await executeStrategy(long1, ONE_ETH);

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      //await injectFakeProfits(long1, ONE_ETH.mul(200));
      await finalizeStrategy(long1);
    });
  });
});
