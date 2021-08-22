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
      strategy11,
      strategy21,
      signer2,
      signer3,
      uniswapV3TradeIntegration,
    } = await setupTests()());

    strategyDataset = await ethers.getContractAt('Strategy', strategy11);
    strategyCandidate = await ethers.getContractAt('Strategy', strategy21);

    wethToken = await ethers.getContractAt(
      '@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20',
      addresses.tokens.WETH,
    );
  });

  describe('Strategies support test', async function () {
    [
      { token: addresses.tokens.PILOT, name: 'PILOT' },
      { token: addresses.tokens.PERP, name: 'PERP' },
    ].forEach(({ token, name }) => {
      it(`should correctly execute a long strategy in ${name} asset on 20210731 from Hermes garden`, async function () {
        let DAI = addresses.tokens.DAI;
        await transferFunds(DAI);
        const garden = await createGarden({ reserveAsset: DAI });
        const gardenReserveAsset = await ethers.getContractAt(
          '@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20',
          DAI,
        );
        await depositFunds(DAI, garden);

        const long1 = await getStrategy({
          kind: 'buy',
          state: 'vote',
          garden: garden1,
          integration: uniswapV3TradeIntegration.address,
          specificParams: [token, 0],
        });

        await executeStrategy(long1, ONE_ETH);

        increaseTime(ONE_DAY_IN_SECONDS * 30);

        //await injectFakeProfits(long1, ONE_ETH.mul(200));
        await finalizeStrategy(long1);
      });
    });
  });
});
