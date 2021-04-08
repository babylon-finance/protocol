// We import Chai to use its asserting functions here.

const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { EMPTY_BYTES, ONE_DAY_IN_SECONDS } = require('../utils/constants');
const { loadFixture } = waffle;

const {
  createStrategy,
  executeStrategy,
  finalizeStrategy,
  injectFakeProfits,
} = require('./fixtures/StrategyHelper.js');
const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require('./../utils/system.js');

const addresses = require('../utils/addresses');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');
const { BigNumber } = require('@ethersproject/bignumber');

// `describe` is a Mocha function that allows you to organize your tests. It's
// not actually needed, but having your tests organized makes debugging them
// easier. All Mocha functions are available in the global scope.

// `describe` receives the name of a section of your test suite, and a callback.
// The callback must define the tests of that section. This callback can't be
// an async function.

async function finishStrategyQ1(garden, strategy, fee = 0) {
  ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]); // TO HAVE STRATEGIES WITHIN THE SAME EPOCH
  await updateTWAPs(garden);
  return strategy.finalizeInvestment(fee, { gasPrice: 0 });
}

async function finishStrategyQ1_noIncreaseTime(garden, strategy, fee = 0) {
  //ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]); // TO HAVE STRATEGIES WITHIN THE SAME EPOCH
  await updateTWAPs(garden);
  return strategy.finalizeInvestment(fee, { gasPrice: 0 });
}

async function finishStrategy2Q(garden, strategy, fee = 0) {
  ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]); // TO HAVE STRATEGIES OF 2 EPOCH DURATION
  await updateTWAPs(garden);
  return strategy.finalizeInvestment(fee, { gasPrice: 0 });
}

async function finishStrategy3Q(garden, strategy, fee = 0) {
  ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 180]); //TO HAVE STRATEGIES LASTING >2 EPOCH
  await updateTWAPs(garden);
  return strategy.finalizeInvestment(fee, { gasPrice: 0 });
}

async function finishStrategy2Y(garden, strategy, fee = 0) {
  ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 365 * 2]); //TO HAVE STRATEGIES LASTING >2 EPOCH
  await updateTWAPs(garden);
  return strategy.finalizeInvestment(fee, { gasPrice: 0 });
}

async function checkStrategyStateExecuting(strategyContract) {
  const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyContract.getStrategyState();

  // Should be active
  expect(address).to.equal(strategyContract.address);
  expect(active).to.equal(true);
  expect(dataSet).to.equal(true);
  expect(finalized).to.equal(false);
  expect(executedAt).to.not.equal(0);
  expect(exitedAt).to.equal(ethers.BigNumber.from(0));

  return [address, active, dataSet, finalized, executedAt, exitedAt];
}

async function checkStrategyStateFinalized(strategyContract) {
  const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyContract.getStrategyState();

  // Should be active
  expect(address).to.equal(strategyContract.address);
  expect(active).to.equal(false);
  expect(dataSet).to.equal(true);
  expect(finalized).to.equal(true);
  expect(executedAt).to.not.equal(0);
  expect(exitedAt).to.not.equal(0);

  return [address, active, dataSet, finalized, executedAt, exitedAt];
}

async function checkProtocolWithParams(_protocol, _principal, _executedAt, _quarter, _timeListPointer, _power) {
  expect(_protocol[0]).to.equal(_principal);
  expect(_protocol[1]).to.equal(_executedAt);
  expect(_protocol[2]).to.equal(_quarter);
  expect(_protocol[3]).to.equal(_timeListPointer);
  expect(_protocol[4]).to.equal(_power);
}

async function checkQuarterWithParams(
  _quarter0,
  _quarter1,
  _quarter2,
  _quarter3,
  _principal,
  _quarter,
  _power,
  _supply,
) {
  expect(_quarter0).to.equal(_principal);
  expect(_quarter1).to.equal(_quarter);
  expect(_quarter2).to.equal(_power);
  expect(_quarter3).to.equal(_supply);
}

async function updateTWAPs(garden) {
  const controller = await ethers.getContractAt('BabController', await garden.controller());
  const priceOracle = await ethers.getContractAt('PriceOracle', await controller.getPriceOracle());
  const adapterAddress = (await priceOracle.getAdapters())[0];
  const adapter = await ethers.getContractAt('UniswapTWAP', adapterAddress);
  for (let i = 0; i < TWAP_ORACLE_GRANULARITY; i += 1) {
    await adapter.update(addresses.tokens.WETH, addresses.tokens.USDC);
    await adapter.update(addresses.tokens.WETH, addresses.tokens.DAI);
    // await adapter.update(addresses.tokens.WETH, addresses.tokens.WBTC);
    // await adapter.update(addresses.tokens.WETH, addresses.tokens.UNI);
    // await adapter.update(addresses.tokens.WETH, addresses.tokens.BAL);
    // await adapter.update(addresses.tokens.WETH, addresses.tokens.COMP);
    ethers.provider.send('evm_increaseTime', [TWAP_ORACLE_WINDOW / TWAP_ORACLE_GRANULARITY]);
  }
}

describe('BABL Rewards Distributor', function () {
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let babController;
  let bablToken;
  let rewardsDistributor;
  let garden1;
  let garden2;
  let strategy11;
  let strategy11Contract;
  let strategy21;
  let strategy21Contract;
  let weth;
  let kyberTradeIntegration;

  beforeEach(async () => {
    ({
      owner,
      signer1,
      signer2,
      signer3,
      garden1,
      garden2,
      strategy11,
      strategy21,
      babController,
      bablToken,
      rewardsDistributor,
      kyberTradeIntegration,
    } = await loadFixture(deployFolioFixture));

    wethToken = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
    strategy11Contract = await ethers.getContractAt('Strategy', strategy11);
    strategy21Contract = await ethers.getContractAt('Strategy', strategy21);
  });

  // You can nest describe calls to create subsections.
  describe('Deployment', function () {
    // `it` is another Mocha function. This is the one you use to define your
    // tests. It receives the test name, and a callback function.

    it('should successfully deploy BABL Mining Rewards Distributor contract', async function () {
      const deployedc = await rewardsDistributor.deployed(bablToken.address, babController.address);
      expect(!!deployedc).to.equal(true);
    });
  });

  describe('Strategy BABL Mining Rewards Calculation', async function () {
    it('should fail trying to calculate rewards of a strategy that has not ended yet', async function () {
      const strategyContract = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );
      // It is executed
      await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42);

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await checkStrategyStateExecuting(
        strategyContract,
      );

      await expect(rewardsDistributor.getStrategyRewards(strategyContract.address)).to.be.revertedWith(
        'The strategy has to be finished before calculations',
      );
    });

    it('should calculate correct BABL in case of 1 strategy with negative profit and total duration of 1 quarter', async function () {
      const strategyContract = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // It is executed
      await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42);

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await checkStrategyStateExecuting(
        strategyContract,
      );

      // Check protocol
      const protocol = await rewardsDistributor.checkProtocol(executedAt);
      await checkProtocolWithParams(protocol, ethers.utils.parseEther('1'), executedAt, 1, 0, 0);

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
      const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
      await checkQuarterWithParams(
        quarterPrincipal,
        quarterNumber,
        quarterPower,
        quarterSupply,
        ethers.utils.parseEther('1'),
        1,
        0,
        await rewardsDistributor.tokenSupplyPerQuarter(1),
      );

      expect(active).to.equal(true);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.not.equal(0);
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      await finishStrategyQ1(garden1, strategyContract, 42);

      const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await checkStrategyStateFinalized(
        strategyContract,
      );

      // Check strategy
      expect(finalized2).to.equal(true);
      expect(executedAt2).to.not.equal(0);
      expect(exitedAt2).to.not.equal(0);

      // Check protocol update

      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt2);
      const [
        protocolPrincipal2,
        protocolTime2,
        protocolquarterBelonging2,
        protocolTimeListPointer2,
        protocolPower2,
      ] = protocol2;

      expect(protocolPrincipal2).to.equal(0);
      expect(protocolquarterBelonging2).to.equal(1);
      expect(protocolPower2).to.not.equal(0); // TODO CHECK EXACT AMOUNT

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
      const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
      await checkQuarterWithParams(
        quarterPrincipal2,
        quarterNumber2,
        quarterPower2,
        quarterSupply2,
        protocolPrincipal2,
        1,
        protocolPower2,
        await rewardsDistributor.tokenSupplyPerQuarter(1),
      );

      const bablRewards1 = await strategyContract.strategyRewards();
    });

    it('should calculate correct BABL in case of 1 strategy with positive profit and with total duration of 1 quarter', async function () {
      const strategyContract = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );
      // It is executed
      await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42);

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await checkStrategyStateExecuting(
        strategyContract,
      );
      // Check strategy
      expect(active).to.equal(true);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.not.equal(0);
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));

      // Check protocol
      const protocol = await rewardsDistributor.checkProtocol(executedAt);
      await checkProtocolWithParams(protocol, ethers.utils.parseEther('1'), executedAt, 1, 0, 0);

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
      const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
      await checkQuarterWithParams(
        quarterPrincipal,
        quarterNumber,
        quarterPower,
        quarterSupply,
        ethers.utils.parseEther('1'),
        1,
        0,
        await rewardsDistributor.tokenSupplyPerQuarter(1),
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      await injectFakeProfits(strategyContract, ethers.utils.parseEther('222'));

      await finishStrategyQ1(garden1, strategyContract, 42);

      const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await checkStrategyStateFinalized(
        strategyContract,
      );
      // Check strategy
      expect(finalized2).to.equal(true);
      expect(executedAt2).to.not.equal(0);
      expect(exitedAt2).to.not.equal(0);

      // Check protocol update

      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt2);
      const [
        protocolPrincipal2,
        protocolTime2,
        protocolquarterBelonging2,
        protocolTimeListPointer2,
        protocolPower2,
      ] = protocol2;

      expect(protocolPrincipal2).to.equal(0);
      expect(protocolquarterBelonging2).to.equal(1);
      expect(protocolPower2).to.not.equal(0); // TODO CHECK EXACT AMOUNT

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
      const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
      await checkQuarterWithParams(
        quarterPrincipal2,
        quarterNumber2,
        quarterPower2,
        quarterSupply2,
        protocolPrincipal2,
        1,
        protocolPower2,
        await rewardsDistributor.tokenSupplyPerQuarter(1),
      );

      const bablRewards1 = await strategyContract.strategyRewards();
    });

    it('should calculate correct BABL in case of 2 strategies with total duration of 1 quarter', async function () {
      // Create strategy 1

      const strategyContract = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Create strategy 2

      const strategyContract2 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Execute strategy 1
      await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42); // Strategy 1

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await checkStrategyStateExecuting(
        strategyContract,
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      // Execute strategy 2, 2 days later

      await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('2'), 42); // Strategy 2

      const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await checkStrategyStateExecuting(
        strategyContract2,
      );

      // Check protocol
      const protocol = await rewardsDistributor.checkProtocol(executedAt2);
      await checkProtocolWithParams(protocol, ethers.utils.parseEther('3'), executedAt2, 1, 1, protocol[4]);

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
      const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
      await checkQuarterWithParams(
        quarterPrincipal,
        quarterNumber,
        quarterPower,
        quarterSupply,
        ethers.utils.parseEther('3'),
        1,
        protocol[4],
        await rewardsDistributor.tokenSupplyPerQuarter(1),
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      await finishStrategyQ1(garden1, strategyContract, 42);

      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract,
      );

      // Check protocol
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      await checkProtocolWithParams(protocol2, ethers.utils.parseEther('2'), exitedAt3, 1, 2, protocol2[4]); // TODO CHECK EXACT AMOUNT

      expect(protocol2[4]).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
      const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
      await checkQuarterWithParams(
        quarterPrincipal2,
        quarterNumber2,
        quarterPower2,
        quarterSupply2,
        protocol2[0],
        1,
        protocol2[4],
        await rewardsDistributor.tokenSupplyPerQuarter(1),
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      await finishStrategyQ1(garden1, strategyContract2, 42);
      const [address4, active4, dataSet4, finalized4, executedAt4, exitedAt4] = await checkStrategyStateFinalized(
        strategyContract2,
      );

      // Check protocol
      const protocol3 = await rewardsDistributor.checkProtocol(exitedAt4);
      await checkProtocolWithParams(protocol3, ethers.utils.parseEther('0'), exitedAt4, 1, 3, protocol3[4]); // TODO CHECK EXACT AMOUNT

      expect(protocol3[4]).to.not.equal(0); // TODO CHECK EXACT AMOUNT

      const protocolQuarter3 = await rewardsDistributor.checkQuarter(protocol3[2]);
      const [quarterPrincipal3, quarterNumber3, quarterPower3, quarterSupply3] = protocolQuarter3;
      await checkQuarterWithParams(
        quarterPrincipal3,
        quarterNumber3,
        quarterPower3,
        quarterSupply3,
        protocol3[0],
        1,
        protocol3[4],
        await rewardsDistributor.tokenSupplyPerQuarter(1),
      );

      const bablRewards1 = await strategyContract.strategyRewards();
      const bablRewards2 = await strategyContract2.strategyRewards();
    });

    it('should calculate correct BABL in case of 3 strategies with total duration of 1 quarter', async function () {
      // Create strategy 1

      const strategyContract1 = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Create strategy 2

      const strategyContract2 = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Create strategy 3

      const strategyContract3 = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Execute strategy 1
      await executeStrategy(garden1, strategyContract1, ethers.utils.parseEther('1'), 42); // Strategy 1

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await checkStrategyStateExecuting(
        strategyContract1,
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
      // Execute strategy 2
      await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('1'), 42); // Strategy 2
      // Execute strategy 3
      await executeStrategy(garden1, strategyContract3, ethers.utils.parseEther('1'), 42); // Strategy 3

      const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await checkStrategyStateExecuting(
        strategyContract3,
      );

      // Check protocol
      const protocol = await rewardsDistributor.checkProtocol(executedAt2);
      await checkProtocolWithParams(protocol, ethers.utils.parseEther('6'), executedAt2, 1, 5, protocol[4]);

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
      const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
      await checkQuarterWithParams(
        quarterPrincipal,
        quarterNumber,
        quarterPower,
        quarterSupply,
        ethers.utils.parseEther('6'),
        1,
        protocol[4],
        await rewardsDistributor.tokenSupplyPerQuarter(1),
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract1, 42);
      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract2, 42);
      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract3, 42);

      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract3,
      );

      // Check protocol
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      await checkProtocolWithParams(protocol2, ethers.utils.parseEther('0'), exitedAt3, 1, 8, protocol2[4]); // TODO CHECK EXACT AMOUNT

      expect(protocol2[4]).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
      const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
      await checkQuarterWithParams(
        quarterPrincipal2,
        quarterNumber2,
        quarterPower2,
        quarterSupply2,
        protocol2[0],
        1,
        protocol2[4],
        await rewardsDistributor.tokenSupplyPerQuarter(1),
      );

      const bablRewards1 = await strategyContract1.strategyRewards();
      const bablRewards2 = await strategyContract2.strategyRewards();
      const bablRewards3 = await strategyContract3.strategyRewards();
    });

    it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with total duration of less than 1 quarter', async function () {
      // Create strategy 1

      const strategyContract1 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Create strategy 2

      const strategyContract2 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Create strategy 3

      const strategyContract3 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden2,
      );

      // Create strategy 4

      const strategyContract4 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden2,
      );
      // Create strategy 5

      const strategyContract5 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden2,
      );
      // Execute strategy 1
      await executeStrategy(garden1, strategyContract1, ethers.utils.parseEther('1'), 42); // Strategy 1

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await checkStrategyStateExecuting(
        strategyContract1,
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
      // Execute strategy 2
      await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('1'), 42); // Strategy 2
      // Execute strategy 3
      await executeStrategy(garden2, strategyContract3, ethers.utils.parseEther('1'), 42); // Strategy 3

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
      // Execute strategy 4
      await executeStrategy(garden2, strategyContract4, ethers.utils.parseEther('1'), 42); // Strategy 4
      // Execute strategy 5
      await executeStrategy(garden2, strategyContract5, ethers.utils.parseEther('1'), 42); // Strategy 5

      const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await checkStrategyStateExecuting(
        strategyContract5,
      );

      // Check protocol
      const protocol = await rewardsDistributor.checkProtocol(executedAt2);
      await checkProtocolWithParams(protocol, ethers.utils.parseEther('5'), executedAt2, 1, 4, protocol[4]);

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
      const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
      await checkQuarterWithParams(
        quarterPrincipal,
        quarterNumber,
        quarterPower,
        quarterSupply,
        ethers.utils.parseEther('5'),
        1,
        protocol[4],
        await rewardsDistributor.tokenSupplyPerQuarter(1),
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract1, 42);
      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract2, 42);
      await finishStrategyQ1_noIncreaseTime(garden2, strategyContract3, 42);
      await finishStrategyQ1_noIncreaseTime(garden2, strategyContract4, 42);
      await finishStrategyQ1_noIncreaseTime(garden2, strategyContract5, 42);

      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract5,
      );

      // Check protocol
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      await checkProtocolWithParams(protocol2, ethers.utils.parseEther('0'), exitedAt3, 1, 9, protocol2[4]); // TODO CHECK EXACT AMOUNT

      expect(protocol2[4]).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
      const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
      await checkQuarterWithParams(
        quarterPrincipal2,
        quarterNumber2,
        quarterPower2,
        quarterSupply2,
        protocol2[0],
        1,
        protocol2[4],
        await rewardsDistributor.tokenSupplyPerQuarter(1),
      );

      const bablRewards1 = await strategyContract1.strategyRewards();
      const bablRewards2 = await strategyContract2.strategyRewards();
      const bablRewards3 = await strategyContract3.strategyRewards();
      const bablRewards4 = await strategyContract4.strategyRewards();
      const bablRewards5 = await strategyContract5.strategyRewards();
    });

    it('should calculate correct BABL in case of 1 strategy with total duration of 2 quarters', async function () {
      // Create strategy 1

      const strategyContract1 = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Execute strategy 1
      await executeStrategy(garden1, strategyContract1, ethers.utils.parseEther('1'), 42); // Strategy 1

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await checkStrategyStateExecuting(
        strategyContract1,
      );

      // Check protocol
      const protocol = await rewardsDistributor.checkProtocol(executedAt);
      await checkProtocolWithParams(protocol, ethers.utils.parseEther('2'), executedAt, 1, 1, protocol[4]);

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
      const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
      await checkQuarterWithParams(
        quarterPrincipal,
        quarterNumber,
        quarterPower,
        quarterSupply,
        ethers.utils.parseEther('2'),
        1,
        protocol[4],
        await rewardsDistributor.tokenSupplyPerQuarter(1),
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategy2Q(garden1, strategyContract1, 42);

      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract1,
      );

      // Check protocol
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      await checkProtocolWithParams(protocol2, ethers.utils.parseEther('0'), exitedAt3, 2, 2, protocol2[4]); // TODO CHECK EXACT AMOUNT

      expect(protocol2[4]).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
      const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
      await checkQuarterWithParams(
        quarterPrincipal2,
        quarterNumber2,
        quarterPower2,
        quarterSupply2,
        protocol2[0],
        2,
        quarterPower2,
        await rewardsDistributor.tokenSupplyPerQuarter(2),
      );

      expect(protocol2[4]).to.gt(quarterPower2);

      const bablRewards1 = await strategyContract1.strategyRewards();
    });

    it('should calculate correct BABL in the future (10 years) in case of 1 strategy with total duration of 2 quarters', async function () {
      // We go to the future 10 years
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 3650]);

      // Create strategy 1

      const strategyContract1 = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Execute strategy 1
      await executeStrategy(garden1, strategyContract1, ethers.utils.parseEther('1'), 42); // Strategy 1

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await checkStrategyStateExecuting(
        strategyContract1,
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategy2Q(garden1, strategyContract1, 42);

      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract1,
      );

      // Check protocol
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      await checkProtocolWithParams(protocol2, ethers.utils.parseEther('0'), exitedAt3, 42, 2, protocol2[4]); // TODO CHECK EXACT AMOUNT
      // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

      expect(protocol2[4]).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
      const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
      await checkQuarterWithParams(
        quarterPrincipal2,
        quarterNumber2,
        quarterPower2,
        quarterSupply2,
        protocol2[0],
        42,
        quarterPower2,
        await rewardsDistributor.tokenSupplyPerQuarter(42),
      );
      // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

      expect(protocol2[4]).to.gt(quarterPower2);

      const bablRewards1 = await strategyContract1.strategyRewards();
    });

    it('should calculate correct BABL rewards in case of 1 strategy with total duration of 3 quarters', async function () {
      // Create strategy 1

      const strategyContract1 = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Execute strategy 1
      await executeStrategy(garden1, strategyContract1, ethers.utils.parseEther('1'), 42); // Strategy 1

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await checkStrategyStateExecuting(
        strategyContract1,
      );
      // Check protocol
      const protocol = await rewardsDistributor.checkProtocol(executedAt);
      await checkProtocolWithParams(protocol, ethers.utils.parseEther('2'), executedAt, 1, 1, protocol[4]);
      // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
      const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
      await checkQuarterWithParams(
        quarterPrincipal,
        quarterNumber,
        quarterPower,
        quarterSupply,
        ethers.utils.parseEther('2'),
        1,
        protocol[4],
        await rewardsDistributor.tokenSupplyPerQuarter(1),
      );
      // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategy3Q(garden1, strategyContract1, 42);

      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract1,
      );

      // Check protocol
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      await checkProtocolWithParams(protocol2, ethers.utils.parseEther('0'), exitedAt3, 3, 2, protocol2[4]); // TODO CHECK EXACT AMOUNT
      // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

      expect(protocol2[4]).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
      const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
      await checkQuarterWithParams(
        quarterPrincipal2,
        quarterNumber2,
        quarterPower2,
        quarterSupply2,
        protocol2[0],
        3,
        quarterPower2,
        await rewardsDistributor.tokenSupplyPerQuarter(3),
      );
      // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

      expect(protocol2[4]).to.gt(quarterPower2);

      expect(quarterPrincipal2).to.equal(protocol2[0]); // All are voter strategies

      const bablRewards1 = await strategyContract1.strategyRewards();
    });

    it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with different timings along 3 quarters', async function () {
      // Create strategy 1

      const strategyContract1 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Create strategy 2

      const strategyContract2 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Create strategy 3

      const strategyContract3 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden2,
      );

      // Create strategy 4

      const strategyContract4 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden2,
      );
      // Create strategy 5

      const strategyContract5 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden2,
      );
      // Execute strategy 1
      await executeStrategy(garden1, strategyContract1, ethers.utils.parseEther('1'), 42); // Strategy 1

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await checkStrategyStateExecuting(
        strategyContract1,
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
      // Execute strategy 2
      await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('1'), 42); // Strategy 2
      // Execute strategy 3
      await executeStrategy(garden2, strategyContract3, ethers.utils.parseEther('1'), 42); // Strategy 3

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
      // Execute strategy 4
      await executeStrategy(garden2, strategyContract4, ethers.utils.parseEther('1'), 42); // Strategy 4
      // Execute strategy 5
      await executeStrategy(garden2, strategyContract5, ethers.utils.parseEther('1'), 42); // Strategy 5

      const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await checkStrategyStateExecuting(
        strategyContract5,
      );

      // Check protocol
      const protocol = await rewardsDistributor.checkProtocol(executedAt2);
      await checkProtocolWithParams(protocol, ethers.utils.parseEther('5'), executedAt2, 1, 4, protocol[4]);
      // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
      const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
      await checkQuarterWithParams(
        quarterPrincipal,
        quarterNumber,
        quarterPower,
        quarterSupply,
        ethers.utils.parseEther('5'),
        1,
        protocol[4],
        await rewardsDistributor.tokenSupplyPerQuarter(1),
      );
      // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract1, 42);
      await finishStrategy2Q(garden1, strategyContract2, 42);
      await finishStrategyQ1_noIncreaseTime(garden2, strategyContract3, 42);
      await finishStrategy2Q(garden2, strategyContract4, 42);
      await finishStrategy3Q(garden2, strategyContract5, 42);
      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract5,
      );

      // Check protocol
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      await checkProtocolWithParams(protocol2, ethers.utils.parseEther('0'), exitedAt3, 5, 9, protocol2[4]); // TODO CHECK EXACT AMOUNT
      // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
      const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
      await checkQuarterWithParams(
        quarterPrincipal2,
        quarterNumber2,
        quarterPower2,
        quarterSupply2,
        protocol2[0],
        5,
        quarterPower2,
        await rewardsDistributor.tokenSupplyPerQuarter(5),
      );
      // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

      const bablRewards1 = await strategyContract1.strategyRewards();
      const bablRewards2 = await strategyContract2.strategyRewards();
      const bablRewards3 = await strategyContract3.strategyRewards();
      const bablRewards4 = await strategyContract4.strategyRewards();
      const bablRewards5 = await strategyContract5.strategyRewards();
    });

    it('should calculate correct BABL (in 10 Years from now) in case of 5 strategies of 2 different Gardens with different timings along 3 quarters', async function () {
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 3650]);

      // Create strategy 1

      const strategyContract1 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Create strategy 2

      const strategyContract2 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Create strategy 3

      const strategyContract3 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden2,
      );

      // Create strategy 4

      const strategyContract4 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden2,
      );
      // Create strategy 5

      const strategyContract5 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden2,
      );
      // Execute strategy 1
      await executeStrategy(garden1, strategyContract1, ethers.utils.parseEther('1'), 42); // Strategy 1

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await checkStrategyStateExecuting(
        strategyContract1,
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
      // Execute strategy 2
      await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('1'), 42); // Strategy 2
      // Execute strategy 3
      await executeStrategy(garden2, strategyContract3, ethers.utils.parseEther('1'), 42); // Strategy 3

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
      // Execute strategy 4
      await executeStrategy(garden2, strategyContract4, ethers.utils.parseEther('1'), 42); // Strategy 4
      // Execute strategy 5
      await executeStrategy(garden2, strategyContract5, ethers.utils.parseEther('1'), 42); // Strategy 5

      const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await checkStrategyStateExecuting(
        strategyContract5,
      );
      // Check protocol
      const protocol = await rewardsDistributor.checkProtocol(executedAt2);
      await checkProtocolWithParams(protocol, ethers.utils.parseEther('5'), executedAt2, 41, 4, protocol[4]);
      // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
      const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
      await checkQuarterWithParams(
        quarterPrincipal,
        quarterNumber,
        quarterPower,
        quarterSupply,
        ethers.utils.parseEther('5'),
        41,
        protocol[4],
        await rewardsDistributor.tokenSupplyPerQuarter(41),
      );
      // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract1, 42);
      await finishStrategy2Q(garden1, strategyContract2, 42);
      await finishStrategyQ1_noIncreaseTime(garden2, strategyContract3, 42);
      await finishStrategy2Q(garden2, strategyContract4, 42);
      await finishStrategy3Q(garden2, strategyContract5, 42);
      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract5,
      );

      // Check protocol
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      await checkProtocolWithParams(protocol2, ethers.utils.parseEther('0'), exitedAt3, 46, 9, protocol2[4]); // TODO CHECK EXACT AMOUNT
      // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
      const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
      await checkQuarterWithParams(
        quarterPrincipal2,
        quarterNumber2,
        quarterPower2,
        quarterSupply2,
        protocol2[0],
        46,
        quarterPower2,
        await rewardsDistributor.tokenSupplyPerQuarter(46),
      );
      // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

      expect(quarterPrincipal2).to.equal(protocol2[0]);

      const bablRewards1 = await strategyContract1.strategyRewards();
      const bablRewards2 = await strategyContract2.strategyRewards();
      const bablRewards3 = await strategyContract3.strategyRewards();
      const bablRewards4 = await strategyContract4.strategyRewards();
      const bablRewards5 = await strategyContract5.strategyRewards();
    });

    it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with different timings along 3 Years', async function () {
      // Create strategy 1

      const strategyContract1 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Create strategy 2

      const strategyContract2 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Create strategy 3

      const strategyContract3 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden2,
      );

      // Create strategy 4

      const strategyContract4 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden2,
      );
      // Create strategy 5

      const strategyContract5 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden2,
      );
      // Execute strategy 1
      await executeStrategy(garden1, strategyContract1, ethers.utils.parseEther('1'), 42); // Strategy 1

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await checkStrategyStateExecuting(
        strategyContract1,
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
      // Execute strategy 2
      await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('1'), 42); // Strategy 2
      // Execute strategy 3
      await executeStrategy(garden2, strategyContract3, ethers.utils.parseEther('1'), 42); // Strategy 3

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
      // Execute strategy 4
      await executeStrategy(garden2, strategyContract4, ethers.utils.parseEther('1'), 42); // Strategy 4
      // Execute strategy 5
      await executeStrategy(garden2, strategyContract5, ethers.utils.parseEther('1'), 42); // Strategy 5

      const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await checkStrategyStateExecuting(
        strategyContract5,
      );

      // Check protocol
      const protocol = await rewardsDistributor.checkProtocol(executedAt2);
      await checkProtocolWithParams(protocol, ethers.utils.parseEther('5'), executedAt2, 1, 4, protocol[4]);
      // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
      const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
      await checkQuarterWithParams(
        quarterPrincipal,
        quarterNumber,
        quarterPower,
        quarterSupply,
        ethers.utils.parseEther('5'),
        1,
        protocol[4],
        await rewardsDistributor.tokenSupplyPerQuarter(1),
      );
      // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract1, 42);
      await finishStrategy2Q(garden1, strategyContract2, 42);
      await finishStrategy2Y(garden2, strategyContract3, 42); // Increase time 2 years
      await finishStrategy2Q(garden2, strategyContract4, 42);
      await finishStrategy3Q(garden2, strategyContract5, 42);
      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract5,
      );

      // Check protocol
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      await checkProtocolWithParams(protocol2, ethers.utils.parseEther('0'), exitedAt3, 13, 9, protocol2[4]); // TODO CHECK EXACT AMOUNT
      // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
      const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
      await checkQuarterWithParams(
        quarterPrincipal2,
        quarterNumber2,
        quarterPower2,
        quarterSupply2,
        protocol2[0],
        13,
        quarterPower2,
        await rewardsDistributor.tokenSupplyPerQuarter(13),
      );
      // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

      expect(quarterPrincipal2).to.equal(protocol2[0]);

      const bablRewards1 = await strategyContract1.strategyRewards();
      const bablRewards2 = await strategyContract2.strategyRewards();
      const bablRewards3 = await strategyContract3.strategyRewards();
      const bablRewards4 = await strategyContract4.strategyRewards();
      const bablRewards5 = await strategyContract5.strategyRewards();
    });

    it('should calculate correct BABL in case of 5 (4 with positive profits) strategies of 2 different Gardens with different timings along 3 Years', async function () {
      // Create strategy 1

      const strategyContract1 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Create strategy 2

      const strategyContract2 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // Create strategy 3

      const strategyContract3 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden2,
      );

      // Create strategy 4

      const strategyContract4 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden2,
      );
      // Create strategy 5

      const strategyContract5 = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden2,
      );
      // Execute strategy 1
      await executeStrategy(garden1, strategyContract1, ethers.utils.parseEther('1'), 42); // Strategy 1

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await checkStrategyStateExecuting(
        strategyContract1,
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
      // Execute strategy 2
      await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('1'), 42); // Strategy 2
      // Execute strategy 3
      await executeStrategy(garden2, strategyContract3, ethers.utils.parseEther('1'), 42); // Strategy 3

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
      // Execute strategy 4
      await executeStrategy(garden2, strategyContract4, ethers.utils.parseEther('1'), 42); // Strategy 4
      // Execute strategy 5
      await executeStrategy(garden2, strategyContract5, ethers.utils.parseEther('1'), 42); // Strategy 5

      const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await checkStrategyStateExecuting(
        strategyContract5,
      );

      // Check protocol
      const protocol = await rewardsDistributor.checkProtocol(executedAt2);
      await checkProtocolWithParams(protocol, ethers.utils.parseEther('5'), executedAt2, 1, 4, protocol[4]);
      // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
      const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
      await checkQuarterWithParams(
        quarterPrincipal,
        quarterNumber,
        quarterPower,
        quarterSupply,
        ethers.utils.parseEther('5'),
        1,
        protocol[4],
        await rewardsDistributor.tokenSupplyPerQuarter(1),
      );
      // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await injectFakeProfits(strategyContract1, ethers.utils.parseEther('200'));
      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract1, 42);

      await finishStrategy2Q(garden1, strategyContract2, 42);

      await injectFakeProfits(strategyContract3, ethers.utils.parseEther('200'));
      await finishStrategy2Y(garden2, strategyContract3, 42); // Increase time 2 years

      await injectFakeProfits(strategyContract4, ethers.utils.parseEther('222'));
      await finishStrategy2Q(garden2, strategyContract4, 42);

      await injectFakeProfits(strategyContract5, ethers.utils.parseEther('222'));
      await finishStrategy3Q(garden2, strategyContract5, 42);
      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract5,
      );

      // Check protocol
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      await checkProtocolWithParams(protocol2, ethers.utils.parseEther('0'), exitedAt3, 13, 9, protocol2[4]); // TODO CHECK EXACT AMOUNT
      // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
      const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
      await checkQuarterWithParams(
        quarterPrincipal2,
        quarterNumber2,
        quarterPower2,
        quarterSupply2,
        protocol2[0],
        13,
        quarterPower2,
        await rewardsDistributor.tokenSupplyPerQuarter(13),
      );
      // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

      const bablRewards1 = await strategyContract1.strategyRewards();
      const bablRewards2 = await strategyContract2.strategyRewards();
      const bablRewards3 = await strategyContract3.strategyRewards();
      const bablRewards4 = await strategyContract4.strategyRewards();
      const bablRewards5 = await strategyContract5.strategyRewards();
    });

    describe('Claiming Profits and BABL Rewards', function () {
      it('should claim and update balances of Signer 1 either Garden tokens or BABL rewards as contributor of 2 strategies (1 with positive profits and other without them) within a quarter', async function () {
        // Create strategy 1

        const strategyContract = await createStrategy(
          0,
          'vote',
          [signer1, signer2, signer3],
          kyberTradeIntegration.address,
          garden1,
        );

        // Create strategy 2

        const strategyContract2 = await createStrategy(
          0,
          'vote',
          [signer1, signer2, signer3],
          kyberTradeIntegration.address,
          garden1,
        );

        // Execute strategy 1
        await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42); // Strategy 1

        const [address, active, dataSet, finalized, executedAt, exitedAt] = await checkStrategyStateExecuting(
          strategyContract,
        );

        ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

        // Execute strategy 2, 2 days later

        await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('2'), 42); // Strategy 2

        const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await checkStrategyStateExecuting(
          strategyContract2,
        );

        // Check protocol
        const protocol = await rewardsDistributor.checkProtocol(executedAt2);
        await checkProtocolWithParams(protocol, ethers.utils.parseEther('3'), executedAt2, 1, 1, protocol[4]);

        const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
        const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
        await checkQuarterWithParams(
          quarterPrincipal,
          quarterNumber,
          quarterPower,
          quarterSupply,
          ethers.utils.parseEther('3'),
          1,
          protocol[4],
          await rewardsDistributor.tokenSupplyPerQuarter(1),
        );

        ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

        await injectFakeProfits(strategyContract, ethers.utils.parseEther('200'));
        await finishStrategyQ1(garden1, strategyContract, 42);

        const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
          strategyContract,
        );

        // Check protocol
        const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
        await checkProtocolWithParams(protocol2, ethers.utils.parseEther('2'), exitedAt3, 1, 2, protocol2[4]); // TODO CHECK EXACT AMOUNT

        expect(protocol2[4]).to.not.equal(0); // TODO Check exact numbers

        const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
        const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
        await checkQuarterWithParams(
          quarterPrincipal2,
          quarterNumber2,
          quarterPower2,
          quarterSupply2,
          protocol2[0],
          1,
          protocol2[4],
          await rewardsDistributor.tokenSupplyPerQuarter(1),
        );

        ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

        await finishStrategyQ1(garden1, strategyContract2, 42);
        const [address4, active4, dataSet4, finalized4, executedAt4, exitedAt4] = await checkStrategyStateFinalized(
          strategyContract2,
        );

        // Check protocol
        const protocol3 = await rewardsDistributor.checkProtocol(exitedAt4);
        await checkProtocolWithParams(protocol3, ethers.utils.parseEther('0'), exitedAt4, 1, 3, protocol3[4]); // TODO CHECK EXACT AMOUNT

        expect(protocol3[4]).to.not.equal(0); // TODO CHECK EXACT AMOUNT

        const protocolQuarter3 = await rewardsDistributor.checkQuarter(protocol3[2]);
        const [quarterPrincipal3, quarterNumber3, quarterPower3, quarterSupply3] = protocolQuarter3;
        await checkQuarterWithParams(
          quarterPrincipal3,
          quarterNumber3,
          quarterPower3,
          quarterSupply3,
          protocol3[0],
          1,
          protocol3[4],
          await rewardsDistributor.tokenSupplyPerQuarter(1),
        );

        const bablRewards1 = await strategyContract.strategyRewards();
        const bablRewards2 = await strategyContract2.strategyRewards();

        // Transfer 500_000e18 tokens from owner to rewardsDistributor for BABL Mining Program
        const value = ethers.utils.parseEther('500000');
        await bablToken.connect(owner).transfer(rewardsDistributor.address, value);

        // Check Balances
        const ownerBalance = await bablToken.balanceOf(owner.address);
        const rewardsDistributorBalance = await bablToken.balanceOf(rewardsDistributor.address);

        expect(await bablToken.totalSupply()).to.equal(BigInt(ownerBalance) + BigInt(rewardsDistributorBalance));

        // We claim our tokens and check that they are received properly
        await garden1.connect(signer1).claimReturns([strategyContract.address, strategyContract2.address]);
        const signer1Balance1 = await bablToken.balanceOf(signer1.address);
        const signer1Profit1 = await garden1.balanceOf(signer1.address);

        expect(signer1Balance1.toString()).to.gt(ethers.utils.parseEther('41300'));
        expect(signer1Profit1.toString()).to.gt(ethers.utils.parseEther('2'));
      });

      it('should claim and update balances of Signer 1 either Garden tokens or BABL rewards as contributor of 5 strategies (4 with positive profits) of 2 different Gardens with different timings along 3 Years', async function () {
        // Create strategy 1

        const strategyContract1 = await createStrategy(
          0,
          'vote',
          [signer1, signer2, signer3],
          kyberTradeIntegration.address,
          garden1,
        );

        // Create strategy 2

        const strategyContract2 = await createStrategy(
          0,
          'vote',
          [signer1, signer2, signer3],
          kyberTradeIntegration.address,
          garden1,
        );

        // Create strategy 3

        const strategyContract3 = await createStrategy(
          0,
          'vote',
          [signer1, signer2, signer3],
          kyberTradeIntegration.address,
          garden2,
        );

        // Create strategy 4

        const strategyContract4 = await createStrategy(
          0,
          'vote',
          [signer1, signer2, signer3],
          kyberTradeIntegration.address,
          garden2,
        );
        // Create strategy 5

        const strategyContract5 = await createStrategy(
          0,
          'vote',
          [signer1, signer2, signer3],
          kyberTradeIntegration.address,
          garden2,
        );
        // Execute strategy 1
        await executeStrategy(garden1, strategyContract1, ethers.utils.parseEther('1'), 42); // Strategy 1

        const [address, active, dataSet, finalized, executedAt, exitedAt] = await checkStrategyStateExecuting(
          strategyContract1,
        );

        ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
        // Execute strategy 2
        await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('1'), 42); // Strategy 2
        // Execute strategy 3
        await executeStrategy(garden2, strategyContract3, ethers.utils.parseEther('1'), 42); // Strategy 3

        ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
        // Execute strategy 4
        await executeStrategy(garden2, strategyContract4, ethers.utils.parseEther('1'), 42); // Strategy 4
        // Execute strategy 5
        await executeStrategy(garden2, strategyContract5, ethers.utils.parseEther('1'), 42); // Strategy 5

        const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await checkStrategyStateExecuting(
          strategyContract5,
        );

        // Check protocol
        const protocol = await rewardsDistributor.checkProtocol(executedAt2);
        await checkProtocolWithParams(protocol, ethers.utils.parseEther('5'), executedAt2, 1, 4, protocol[4]);
        // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

        const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
        const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
        await checkQuarterWithParams(
          quarterPrincipal,
          quarterNumber,
          quarterPower,
          quarterSupply,
          ethers.utils.parseEther('5'),
          1,
          protocol[4],
          await rewardsDistributor.tokenSupplyPerQuarter(1),
        );
        // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

        ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

        await injectFakeProfits(strategyContract1, ethers.utils.parseEther('200'));
        await finishStrategyQ1_noIncreaseTime(garden1, strategyContract1, 42);

        await finishStrategy2Q(garden1, strategyContract2, 42);

        await injectFakeProfits(strategyContract3, ethers.utils.parseEther('200'));
        await finishStrategy2Y(garden2, strategyContract3, 42); // Increase time 2 years

        await injectFakeProfits(strategyContract4, ethers.utils.parseEther('222'));
        await finishStrategy2Q(garden2, strategyContract4, 42);

        await injectFakeProfits(strategyContract5, ethers.utils.parseEther('222'));
        await finishStrategy3Q(garden2, strategyContract5, 42);
        const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
          strategyContract5,
        );

        // Check protocol
        const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
        await checkProtocolWithParams(protocol2, ethers.utils.parseEther('0'), exitedAt3, 13, 9, protocol2[4]); // TODO CHECK EXACT AMOUNT
        // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

        const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
        const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
        await checkQuarterWithParams(
          quarterPrincipal2,
          quarterNumber2,
          quarterPower2,
          quarterSupply2,
          protocol2[0],
          13,
          quarterPower2,
          await rewardsDistributor.tokenSupplyPerQuarter(13),
        );
        // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

        const bablRewards1 = await strategyContract1.strategyRewards();
        const bablRewards2 = await strategyContract2.strategyRewards();
        const bablRewards3 = await strategyContract3.strategyRewards();
        const bablRewards4 = await strategyContract4.strategyRewards();
        const bablRewards5 = await strategyContract5.strategyRewards();

        // Transfer 500_000e18 tokens from owner to rewardsDistributor for BABL Mining Program
        const value = ethers.utils.parseEther('500000');
        await bablToken.connect(owner).transfer(rewardsDistributor.address, value);

        // Check Balances
        const ownerBalance = await bablToken.balanceOf(owner.address);
        const rewardsDistributorBalance = await bablToken.balanceOf(rewardsDistributor.address);

        expect(await bablToken.totalSupply()).to.equal(BigInt(ownerBalance) + BigInt(rewardsDistributorBalance));

        // We claim our tokens and check that they are received properly
        await garden1.connect(signer1).claimReturns([strategyContract1.address, strategyContract2.address]);
        const signer1Balance1 = await bablToken.balanceOf(signer1.address);
        const signer1Profit1 = await garden1.balanceOf(signer1.address);

        await garden2
          .connect(signer1)
          .claimReturns([strategyContract3.address, strategyContract4.address, strategyContract5.address]);
        const signer1Balance2 = await bablToken.balanceOf(signer1.address);
        const signer1Profit2 = await garden2.balanceOf(signer1.address);

        expect(signer1Balance2.toString()).to.gt(ethers.utils.parseEther('357000'));
        expect(signer1Profit1.toString()).to.gt(ethers.utils.parseEther('3'));
        expect(signer1Profit2.toString()).to.gt(ethers.utils.parseEther('8'));
      });
    });
  });
});
