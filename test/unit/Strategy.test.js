const { expect } = require('chai');
const chaiAsPromised = require('chai-as-promised');
const { ethers } = require('hardhat');
const { fund } = require('lib/whale');

require('chai').use(chaiAsPromised);

const {
  createStrategy,
  executeStrategy,
  finalizeStrategy,
  injectFakeProfits,
  deposit,
  DEFAULT_STRATEGY_PARAMS,
} = require('fixtures/StrategyHelper.js');
const { increaseTime, normalizeDecimals, getERC20, getContract, parse, from, eth } = require('utils/test-helpers');

const addresses = require('lib/addresses');
const { ONE_DAY_IN_SECONDS, ADDRESS_ZERO } = require('lib/constants.js');
const { setupTests } = require('fixtures/GardenFixture');
const { getStrategy } = require('fixtures/StrategyHelper');
const ZEROMAXCAP_STRATEGY_PARAMS = [
  eth(0), // _maxCapitalRequested == 0
  eth(0.1), // _stake
  ONE_DAY_IN_SECONDS * 30, // _strategyDuration
  eth(0.05), // 5% _expectedReturn,
  eth(0.1), // 10% _maxAllocationPercentage,
  eth(0.05), // 5% _maxGasFeePercentage
  eth(0.05), // 5% _maxTradeSlippagePercentage
];

describe('Strategy', function () {
  let strategy;
  let babController;
  let owner;
  let keeper;
  let signer1;
  let signer2;
  let signer3;
  let garden1;
  let garden2;
  let strategy11;
  let strategy21;
  let wethToken;
  let treasury;
  let heart;
  let aaveLendIntegration;
  let uniswapV3TradeIntegration;
  let uniswapPoolIntegration;
  let balancerIntegration;
  let oneInchPoolIntegration;
  let yearnVaultIntegration;
  let masterSwapper;
  let weth;

  beforeEach(async () => {
    [, , owner, signer1, signer2] = await ethers.getSigners();
    const strategyFactory = await ethers.getContractFactory('BabController');
    strategy = await strategyFactory.deploy();
    await strategy.connect(owner).initialize();
  });
});
