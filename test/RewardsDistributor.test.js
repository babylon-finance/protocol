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

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);

      // Protocol principal should be incremented accordingly
      const protocol = await rewardsDistributor.checkProtocol(executedAt);
      const protocolPrincipal = protocol[0];
      const protocolTime = protocol[1];
      const protocolquarterBelonging = protocol[2];
      const protocolTimeListPointer = protocol[3];
      const protocolPower = protocol[4];

      expect(protocolPrincipal).to.equal(ethers.utils.parseEther('1')); // It is vote state strategy
      expect(protocolTime).to.equal(executedAt);
      expect(protocolquarterBelonging).to.equal(1);
      expect(protocolTimeListPointer).to.equal(0); // pid starting by zero
      expect(protocolPower).to.equal(0);

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocolquarterBelonging);
      const quarterPrincipal = protocolQuarter[0];
      const quarterNumber = protocolQuarter[1];
      const quarterPower = protocolQuarter[2];
      const quarterSupply = protocolQuarter[3];

      expect(quarterPrincipal).to.equal(ethers.utils.parseEther('1'));
      expect(quarterNumber).to.equal(1);
      expect(quarterPower).to.equal(0);
      expect(quarterSupply).to.not.equal(0);

      expect(protocolPrincipal).to.equal(ethers.utils.parseEther('1')); // It is vote state strategy
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

      // Protocol principal should be reduced accordingly
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt2);
      const protocolPrincipal2 = protocol2[0];
      const protocolTime2 = protocol2[1];
      const protocolquarterBelonging2 = protocol2[2];
      const protocolTimeListPointer2 = protocol2[3];
      const protocolPower2 = protocol2[4];

      expect(protocolPrincipal2).to.equal(0);
      expect(protocolquarterBelonging2).to.equal(1);
      expect(protocolPower2).to.not.equal(0); // TODO CHECK EXACT AMOUNT
      expect(finalized2).to.equal(true);
      expect(executedAt2).to.not.equal(0);
      expect(exitedAt2).to.not.equal(0);

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocolquarterBelonging2);
      const quarterPrincipal2 = protocolQuarter2[0];
      const quarterNumber2 = protocolQuarter2[1];
      const quarterPower2 = protocolQuarter2[2];
      const quarterSupply2 = protocolQuarter2[3];

      expect(quarterPrincipal2).to.equal(protocolPrincipal2); // It is a voter strategy
      expect(quarterNumber2).to.equal(1);
      expect(quarterPower2).to.equal(protocolPower2);
      expect(quarterSupply2).to.equal(await rewardsDistributor.tokenSupplyPerQuarter(1));

      const bablRewards1 = await strategyContract.strategyRewards();
    });
    /** 
    it.only('should claim contributor Profit and BABL in case of 1 strategy with positive profit and total duration of 1 quarter', async function () {

      await garden1.connect(signer1).deposit(ethers.utils.parseEther('10'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('10'),
        gasPrice: 0,
      });

      await garden1.connect(signer2).deposit(ethers.utils.parseEther('5'), 1, signer2.getAddress(), {
        value: ethers.utils.parseEther('5'),
        gasPrice: 0,
      });
      
      const strategyContract = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // It is executed
      await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42);

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await checkStrategyStateExecuting(strategyContract);
      
      // Protocol principal should be incremented accordingly
      const protocol = await rewardsDistributor.checkProtocol(executedAt);
      const protocolPrincipal = protocol[0];
      const protocolTime = protocol[1];
      const protocolquarterBelonging = protocol[2];
      const protocolTimeListPointer = protocol[3];
      const protocolPower = protocol[4];

      expect(protocolPrincipal).to.equal(ethers.utils.parseEther('1')); // It is vote state strategy
      expect(protocolTime).to.equal(executedAt);
      expect(protocolquarterBelonging).to.equal(1);
      expect(protocolTimeListPointer).to.equal(0); // pid starting by zero
      expect(protocolPower).to.equal(0);

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocolquarterBelonging);
      const quarterPrincipal = protocolQuarter[0];
      const quarterNumber = protocolQuarter[1];
      const quarterPower = protocolQuarter[2];
      const quarterSupply = protocolQuarter[3];

      expect(quarterPrincipal).to.equal(ethers.utils.parseEther('1'));
      expect(quarterNumber).to.equal(1);
      expect(quarterPower).to.equal(0);
      expect(quarterSupply).to.not.equal(0);

      expect(protocolPrincipal).to.equal(ethers.utils.parseEther('1')); // It is vote state strategy
      expect(active).to.equal(true);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.not.equal(0);
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      await injectFakeProfits(strategyContract, ethers.utils.parseEther('222'));

      await finishStrategyQ1(garden1, strategyContract, 42);

      const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await checkStrategyStateFinalized(strategyContract);

      // Protocol principal should be reduced accordingly
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt2);
      const protocolPrincipal2 = protocol2[0];
      const protocolTime2 = protocol2[1];
      const protocolquarterBelonging2 = protocol2[2];
      const protocolTimeListPointer2 = protocol2[3];
      const protocolPower2 = protocol2[4];

      expect(protocolPrincipal2).to.equal(0);
      expect(protocolquarterBelonging2).to.equal(1);
      expect(protocolPower2).to.not.equal(0); // TODO CHECK EXACT AMOUNT
      expect(finalized2).to.equal(true);
      expect(executedAt2).to.not.equal(0);
      expect(exitedAt2).to.not.equal(0);

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocolquarterBelonging2);
      const quarterPrincipal2 = protocolQuarter2[0];
      const quarterNumber2 = protocolQuarter2[1];
      const quarterPower2 = protocolQuarter2[2];
      const quarterSupply2 = protocolQuarter2[3];

      expect(quarterPrincipal2).to.equal(protocolPrincipal2); // It is a voter strategy
      expect(quarterNumber2).to.equal(1);
      expect(quarterPower2).to.equal(protocolPower2);
      expect(quarterSupply2).to.equal(await rewardsDistributor.tokenSupplyPerQuarter(1));

      const bablRewards1 = await strategyContract.strategyRewards();
      console.log('EO');
      await garden1.connect(signer1).claimReturns([strategyContract.address]); // BABL Rewards and Profit claim
      await garden1.connect(signer2).claimReturns([strategyContract.address]); // BABL Rewards and Profit claim

    });
    */

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

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);

      // Protocol principal should be incremented accordingly
      const protocol = await rewardsDistributor.checkProtocol(executedAt);
      const protocolPrincipal = protocol[0];
      const protocolTime = protocol[1];
      const protocolquarterBelonging = protocol[2];
      const protocolTimeListPointer = protocol[3];
      const protocolPower = protocol[4];

      expect(protocolPrincipal).to.equal(ethers.utils.parseEther('1')); // It is vote state strategy
      expect(protocolTime).to.equal(executedAt);
      expect(protocolquarterBelonging).to.equal(1);
      expect(protocolTimeListPointer).to.equal(0); // pid starting by zero
      expect(protocolPower).to.equal(0);

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocolquarterBelonging);
      const quarterPrincipal = protocolQuarter[0];
      const quarterNumber = protocolQuarter[1];
      const quarterPower = protocolQuarter[2];
      const quarterSupply = protocolQuarter[3];

      expect(quarterPrincipal).to.equal(ethers.utils.parseEther('1'));
      expect(quarterNumber).to.equal(1);
      expect(quarterPower).to.equal(0);
      expect(quarterSupply).to.not.equal(0);

      expect(protocolPrincipal).to.equal(ethers.utils.parseEther('1')); // It is vote state strategy
      expect(active).to.equal(true);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.not.equal(0);
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      await injectFakeProfits(strategyContract, ethers.utils.parseEther('222'));

      await finishStrategyQ1(garden1, strategyContract, 42);

      const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await checkStrategyStateFinalized(
        strategyContract,
      );

      // Protocol principal should be reduced accordingly
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt2);
      const protocolPrincipal2 = protocol2[0];
      const protocolTime2 = protocol2[1];
      const protocolquarterBelonging2 = protocol2[2];
      const protocolTimeListPointer2 = protocol2[3];
      const protocolPower2 = protocol2[4];

      expect(protocolPrincipal2).to.equal(0);
      expect(protocolquarterBelonging2).to.equal(1);
      expect(protocolPower2).to.not.equal(0); // TODO CHECK EXACT AMOUNT
      expect(finalized2).to.equal(true);
      expect(executedAt2).to.not.equal(0);
      expect(exitedAt2).to.not.equal(0);

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocolquarterBelonging2);
      const quarterPrincipal2 = protocolQuarter2[0];
      const quarterNumber2 = protocolQuarter2[1];
      const quarterPower2 = protocolQuarter2[2];
      const quarterSupply2 = protocolQuarter2[3];

      expect(quarterPrincipal2).to.equal(protocolPrincipal2); // It is a voter strategy
      expect(quarterNumber2).to.equal(1);
      expect(quarterPower2).to.equal(protocolPower2);
      expect(quarterSupply2).to.equal(await rewardsDistributor.tokenSupplyPerQuarter(1));

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

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      // Execute strategy 2, 2 days later

      await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('2'), 42); // Strategy 2

      const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await checkStrategyStateExecuting(
        strategyContract2,
      );

      // Protocol principal should be incremented accordingly
      const protocol = await rewardsDistributor.checkProtocol(executedAt2);
      const protocolPrincipal = protocol[0];
      const protocolTime = protocol[1];
      const protocolquarterBelonging = protocol[2];
      const protocolTimeListPointer = protocol[3];
      const protocolPower = protocol[4];

      expect(protocolPrincipal).to.equal(ethers.utils.parseEther('3')); // It is vote state strategy
      expect(protocolTime).to.equal(executedAt2);
      expect(protocolquarterBelonging).to.equal(1);
      expect(protocolTimeListPointer).to.equal(1); // pid starting by zero, second strategy
      expect(protocolPower).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocolquarterBelonging);
      const quarterPrincipal = protocolQuarter[0];
      const quarterNumber = protocolQuarter[1];
      const quarterPower = protocolQuarter[2];
      const quarterSupply = protocolQuarter[3];

      expect(quarterPrincipal).to.equal(ethers.utils.parseEther('3'));
      expect(quarterNumber).to.equal(1);
      expect(quarterPower).to.equal(protocolPower);
      expect(quarterSupply).to.not.equal(0);

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      await finishStrategyQ1(garden1, strategyContract, 42);

      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract,
      );

      // Protocol principal should be reduced accordingly
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      const protocolPrincipal2 = protocol2[0];
      const protocolTime2 = protocol2[1];
      const protocolquarterBelonging2 = protocol2[2];
      const protocolTimeListPointer2 = protocol2[3];
      const protocolPower2 = protocol2[4];

      expect(protocolPrincipal2).to.equal(ethers.utils.parseEther('2'));
      expect(protocolquarterBelonging2).to.equal(1);
      expect(protocolPower2).to.not.equal(0); // TODO CHECK EXACT AMOUNT
      expect(protocolTime2).to.equal(exitedAt3);
      expect(protocolTimeListPointer2).to.equal(2); // pid starting by zero, 3rd checkpoint
      expect(protocolPower).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocolquarterBelonging2);
      const quarterPrincipal2 = protocolQuarter2[0];
      const quarterNumber2 = protocolQuarter2[1];
      const quarterPower2 = protocolQuarter2[2];
      const quarterSupply2 = protocolQuarter2[3];

      expect(quarterPrincipal2).to.equal(protocolPrincipal2); // It is a voter strategy
      expect(quarterNumber2).to.equal(1);
      expect(quarterPower2).to.equal(protocolPower2);
      expect(quarterSupply2).to.equal(await rewardsDistributor.tokenSupplyPerQuarter(1));

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      await finishStrategyQ1(garden1, strategyContract2, 42);
      const [address4, active4, dataSet4, finalized4, executedAt4, exitedAt4] = await checkStrategyStateFinalized(
        strategyContract2,
      );

      // Protocol principal should be reduced accordingly
      const protocol3 = await rewardsDistributor.checkProtocol(exitedAt4);
      const protocolPrincipal3 = protocol3[0];
      const protocolTime3 = protocol3[1];
      const protocolquarterBelonging3 = protocol3[2];
      const protocolTimeListPointer3 = protocol3[3];
      const protocolPower3 = protocol3[4];

      expect(protocolPrincipal3).to.equal(0);
      expect(protocolquarterBelonging3).to.equal(1);
      expect(protocolPower3).to.not.equal(0); // TODO CHECK EXACT AMOUNT
      expect(protocolTime3).to.equal(exitedAt4);
      expect(protocolTimeListPointer3).to.equal(3);

      const protocolQuarter3 = await rewardsDistributor.checkQuarter(protocolquarterBelonging3);
      const quarterPrincipal3 = protocolQuarter3[0];
      const quarterNumber3 = protocolQuarter3[1];
      const quarterPower3 = protocolQuarter3[2];
      const quarterSupply3 = protocolQuarter3[3];

      expect(quarterPrincipal3).to.equal(protocolPrincipal3);
      expect(quarterNumber3).to.equal(1);
      expect(quarterPower3).to.equal(protocolPower3);
      expect(quarterSupply3).to.equal(await rewardsDistributor.tokenSupplyPerQuarter(1));

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

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
      // Execute strategy 2
      await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('1'), 42); // Strategy 2
      // Execute strategy 3
      await executeStrategy(garden1, strategyContract3, ethers.utils.parseEther('1'), 42); // Strategy 3

      const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await checkStrategyStateExecuting(
        strategyContract3,
      );

      // Protocol principal should be incremented accordingly
      const protocol = await rewardsDistributor.checkProtocol(executedAt2);
      const protocolPrincipal = protocol[0];
      const protocolTime = protocol[1];
      const protocolquarterBelonging = protocol[2];
      const protocolTimeListPointer = protocol[3];
      const protocolPower = protocol[4];

      expect(protocolPrincipal).to.equal(ethers.utils.parseEther('6')); // All are ADCTIVE state strategies (add 1ETH each)
      expect(protocolTime).to.equal(executedAt2);
      expect(protocolquarterBelonging).to.equal(1);
      expect(protocolTimeListPointer).to.equal(5); // pid starting by zero, 3 strategies launched with 1 additional addinvestment each
      expect(protocolPower).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocolquarterBelonging);
      const quarterPrincipal = protocolQuarter[0];
      const quarterNumber = protocolQuarter[1];
      const quarterPower = protocolQuarter[2];
      const quarterSupply = protocolQuarter[3];

      expect(quarterPrincipal).to.equal(ethers.utils.parseEther('6'));
      expect(quarterNumber).to.equal(1);
      expect(quarterPower).to.equal(protocolPower);
      expect(quarterSupply).to.not.equal(0);

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract1, 42);
      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract2, 42);
      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract3, 42);

      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract3,
      );

      // Protocol principal should be reduced accordingly
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      const protocolPrincipal2 = protocol2[0];
      const protocolTime2 = protocol2[1];
      const protocolquarterBelonging2 = protocol2[2];
      const protocolTimeListPointer2 = protocol2[3];
      const protocolPower2 = protocol2[4];

      expect(protocolPrincipal2).to.equal(ethers.utils.parseEther('0'));
      expect(protocolquarterBelonging2).to.equal(1);
      expect(protocolPower2).to.not.equal(0); // TODO CHECK EXACT AMOUNT
      expect(protocolTime2).to.equal(exitedAt3);
      expect(protocolTimeListPointer2).to.equal(8); // pid starting by zero, 8th checkpoint (3 new strategies executing with 3 adding capitals + 3 finalize investments)
      expect(protocolPower).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocolquarterBelonging2);
      const quarterPrincipal2 = protocolQuarter2[0];
      const quarterNumber2 = protocolQuarter2[1];
      const quarterPower2 = protocolQuarter2[2];
      const quarterSupply2 = protocolQuarter2[3];

      expect(quarterPrincipal2).to.equal(protocolPrincipal2); // All are voter strategies
      expect(quarterNumber2).to.equal(1);
      expect(quarterPower2).to.equal(protocolPower2);
      expect(quarterSupply2).to.equal(await rewardsDistributor.tokenSupplyPerQuarter(1));

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

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);

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

      // Protocol principal should be incremented accordingly
      const protocol = await rewardsDistributor.checkProtocol(executedAt2);
      const protocolPrincipal = protocol[0];
      const protocolTime = protocol[1];
      const protocolquarterBelonging = protocol[2];
      const protocolTimeListPointer = protocol[3];
      const protocolPower = protocol[4];

      expect(protocolPrincipal).to.equal(ethers.utils.parseEther('5')); // All are vote state strategies
      expect(protocolTime).to.equal(executedAt2);
      expect(protocolquarterBelonging).to.equal(1);
      expect(protocolTimeListPointer).to.equal(4); // pid starting by zero, 5 strategies launched
      expect(protocolPower).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocolquarterBelonging);
      const quarterPrincipal = protocolQuarter[0];
      const quarterNumber = protocolQuarter[1];
      const quarterPower = protocolQuarter[2];
      const quarterSupply = protocolQuarter[3];

      expect(quarterPrincipal).to.equal(ethers.utils.parseEther('5'));
      expect(quarterNumber).to.equal(1);
      expect(quarterPower).to.equal(protocolPower);
      expect(quarterSupply).to.not.equal(0);

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract1, 42);
      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract2, 42);
      await finishStrategyQ1_noIncreaseTime(garden2, strategyContract3, 42);
      await finishStrategyQ1_noIncreaseTime(garden2, strategyContract4, 42);
      await finishStrategyQ1_noIncreaseTime(garden2, strategyContract5, 42);

      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract5,
      );

      // Protocol principal should be reduced accordingly
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      const protocolPrincipal2 = protocol2[0];
      const protocolTime2 = protocol2[1];
      const protocolquarterBelonging2 = protocol2[2];
      const protocolTimeListPointer2 = protocol2[3];
      const protocolPower2 = protocol2[4];

      expect(protocolPrincipal2).to.equal(ethers.utils.parseEther('0'));
      expect(protocolquarterBelonging2).to.equal(1);
      expect(protocolPower2).to.not.equal(0); // TODO CHECK EXACT AMOUNT
      expect(protocolTime2).to.equal(exitedAt3);
      expect(protocolTimeListPointer2).to.equal(9); // pid starting by zero, 9th checkpoint
      expect(protocolPower).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocolquarterBelonging2);
      const quarterPrincipal2 = protocolQuarter2[0];
      const quarterNumber2 = protocolQuarter2[1];
      const quarterPower2 = protocolQuarter2[2];
      const quarterSupply2 = protocolQuarter2[3];

      expect(quarterPrincipal2).to.equal(protocolPrincipal2); // All are voter strategies
      expect(quarterNumber2).to.equal(1);
      expect(quarterPower2).to.equal(protocolPower2);
      expect(quarterSupply2).to.equal(await rewardsDistributor.tokenSupplyPerQuarter(1));

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

      // Protocol principal should be increased accordingly
      const protocol = await rewardsDistributor.checkProtocol(executedAt);
      const protocolPrincipal = protocol[0];
      const protocolTime = protocol[1];
      const protocolquarterBelonging = protocol[2];
      const protocolTimeListPointer = protocol[3];
      const protocolPower = protocol[4];

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocolquarterBelonging);
      const quarterPrincipal = protocolQuarter[0];
      const quarterNumber = protocolQuarter[1];
      const quarterPower = protocolQuarter[2];
      const quarterSupply = protocolQuarter[3];

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategy2Q(garden1, strategyContract1, 42);

      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract1,
      );

      // Protocol principal should be reduced accordingly
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      const protocolPrincipal2 = protocol2[0];
      const protocolTime2 = protocol2[1];
      const protocolquarterBelonging2 = protocol2[2];
      const protocolTimeListPointer2 = protocol2[3];
      const protocolPower2 = protocol2[4];

      expect(protocolPrincipal2).to.equal(ethers.utils.parseEther('0'));
      expect(protocolquarterBelonging2).to.equal(2);
      expect(protocolPower2).to.not.equal(0); // TODO CHECK EXACT AMOUNT
      expect(protocolTime2).to.equal(exitedAt3);
      expect(protocolTimeListPointer2).to.equal(2); // pid starting by zero, 1 new strategy, 1 finalized pid++ = 2
      expect(protocolPower2).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocolquarterBelonging2);
      const quarterPrincipal2 = protocolQuarter2[0];
      const quarterNumber2 = protocolQuarter2[1];
      const quarterPower2 = protocolQuarter2[2];
      const quarterSupply2 = protocolQuarter2[3];

      expect(quarterPrincipal2).to.equal(protocolPrincipal2); // All are voter strategies
      expect(quarterNumber2).to.equal(2);

      expect(protocolPower2).to.gt(quarterPower2);
      expect(quarterSupply2).to.equal(await rewardsDistributor.tokenSupplyPerQuarter(2));

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

      // Protocol principal should be increased accordingly
      const protocol = await rewardsDistributor.checkProtocol(executedAt);
      const protocolPrincipal = protocol[0];
      const protocolTime = protocol[1];
      const protocolquarterBelonging = protocol[2];
      const protocolTimeListPointer = protocol[3];
      const protocolPower = protocol[4];

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocolquarterBelonging);
      const quarterPrincipal = protocolQuarter[0];
      const quarterNumber = protocolQuarter[1];
      const quarterPower = protocolQuarter[2];
      const quarterSupply = protocolQuarter[3];

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategy2Q(garden1, strategyContract1, 42);

      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract1,
      );

      // Protocol principal should be reduced accordingly
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      const protocolPrincipal2 = protocol2[0];
      const protocolTime2 = protocol2[1];
      const protocolquarterBelonging2 = protocol2[2];
      const protocolTimeListPointer2 = protocol2[3];
      const protocolPower2 = protocol2[4];

      expect(protocolPrincipal2).to.equal(ethers.utils.parseEther('0'));
      expect(protocolquarterBelonging2).to.equal(42);
      expect(protocolPower2).to.not.equal(0); // TODO CHECK EXACT AMOUNT
      expect(protocolTime2).to.equal(exitedAt3);
      expect(protocolTimeListPointer2).to.equal(2); // pid starting by zero, 1 new strategy, 1 finalized pid++ = 2
      expect(protocolPower2).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocolquarterBelonging2);
      const quarterPrincipal2 = protocolQuarter2[0];
      const quarterNumber2 = protocolQuarter2[1];
      const quarterPower2 = protocolQuarter2[2];
      const quarterSupply2 = protocolQuarter2[3];

      expect(quarterPrincipal2).to.equal(protocolPrincipal2); // All are voter strategies
      expect(quarterNumber2).to.equal(42);

      expect(protocolPower2).to.gt(quarterPower2);
      expect(quarterSupply2).to.equal(await rewardsDistributor.tokenSupplyPerQuarter(42)); // Epoch number 42

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

      // Protocol principal should be increased accordingly
      const protocol = await rewardsDistributor.checkProtocol(executedAt);
      const protocolPrincipal = protocol[0];
      const protocolTime = protocol[1];
      const protocolquarterBelonging = protocol[2];
      const protocolTimeListPointer = protocol[3];
      const protocolPower = protocol[4];

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocolquarterBelonging);
      const quarterPrincipal = protocolQuarter[0];
      const quarterNumber = protocolQuarter[1];
      const quarterPower = protocolQuarter[2];
      const quarterSupply = protocolQuarter[3];

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategy3Q(garden1, strategyContract1, 42);

      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract1,
      );

      // Protocol principal should be reduced accordingly
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      const protocolPrincipal2 = protocol2[0];
      const protocolTime2 = protocol2[1];
      const protocolquarterBelonging2 = protocol2[2];
      const protocolTimeListPointer2 = protocol2[3];
      const protocolPower2 = protocol2[4];

      expect(protocolPrincipal2).to.equal(ethers.utils.parseEther('0'));
      expect(protocolquarterBelonging2).to.equal(3);
      expect(protocolPower2).to.not.equal(0); // TODO CHECK EXACT AMOUNT
      expect(protocolTime2).to.equal(exitedAt3);
      expect(protocolTimeListPointer2).to.equal(2); // pid starting by zero, 1 new strategy, 1 finalized pid++ = 2
      expect(protocolPower2).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocolquarterBelonging2);
      const quarterPrincipal2 = protocolQuarter2[0];
      const quarterNumber2 = protocolQuarter2[1];
      const quarterPower2 = protocolQuarter2[2];
      const quarterSupply2 = protocolQuarter2[3];

      expect(quarterPrincipal2).to.equal(protocolPrincipal2); // All are voter strategies
      expect(quarterNumber2).to.equal(3);

      expect(protocolPower2).to.gt(quarterPower2);
      expect(quarterSupply2).to.equal(await rewardsDistributor.tokenSupplyPerQuarter(3)); // Epoch number 42

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

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);

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

      // Protocol principal should be incremented accordingly
      const protocol = await rewardsDistributor.checkProtocol(executedAt2);
      const protocolPrincipal = protocol[0];
      const protocolTime = protocol[1];
      const protocolquarterBelonging = protocol[2];
      const protocolTimeListPointer = protocol[3];
      const protocolPower = protocol[4];

      expect(protocolPrincipal).to.equal(ethers.utils.parseEther('5')); // All are vote state strategies
      expect(protocolTime).to.equal(executedAt2);
      expect(protocolquarterBelonging).to.equal(1);
      expect(protocolTimeListPointer).to.equal(4); // pid starting by zero, 5 strategies launched
      expect(protocolPower).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocolquarterBelonging);
      const quarterPrincipal = protocolQuarter[0];
      const quarterNumber = protocolQuarter[1];
      const quarterPower = protocolQuarter[2];
      const quarterSupply = protocolQuarter[3];

      expect(quarterPrincipal).to.equal(ethers.utils.parseEther('5'));
      expect(quarterNumber).to.equal(1);
      expect(quarterPower).to.equal(protocolPower);
      expect(quarterSupply).to.not.equal(0);

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract1, 42);
      await finishStrategy2Q(garden1, strategyContract2, 42);
      await finishStrategyQ1_noIncreaseTime(garden2, strategyContract3, 42);
      await finishStrategy2Q(garden2, strategyContract4, 42);
      await finishStrategy3Q(garden2, strategyContract5, 42);
      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract5,
      );

      // Protocol principal should be reduced accordingly
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      const protocolPrincipal2 = protocol2[0];
      const protocolTime2 = protocol2[1];
      const protocolquarterBelonging2 = protocol2[2];
      const protocolTimeListPointer2 = protocol2[3];
      const protocolPower2 = protocol2[4];

      expect(protocolPrincipal2).to.equal(ethers.utils.parseEther('0'));
      expect(protocolquarterBelonging2).to.equal(5);
      expect(protocolPower2).to.not.equal(0); // TODO CHECK EXACT AMOUNT
      expect(protocolTime2).to.equal(exitedAt3);
      expect(protocolTimeListPointer2).to.equal(9); // pid starting by zero, 9th checkpoint
      expect(protocolPower).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocolquarterBelonging2);
      const quarterPrincipal2 = protocolQuarter2[0];
      const quarterNumber2 = protocolQuarter2[1];
      const quarterPower2 = protocolQuarter2[2];
      const quarterSupply2 = protocolQuarter2[3];

      expect(quarterPrincipal2).to.equal(protocolPrincipal2); // All are voter strategies
      expect(quarterNumber2).to.equal(5);
      expect(quarterSupply2).to.equal(await rewardsDistributor.tokenSupplyPerQuarter(5));

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

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);

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

      // Protocol principal should be incremented accordingly
      const protocol = await rewardsDistributor.checkProtocol(executedAt2);
      const protocolPrincipal = protocol[0];
      const protocolTime = protocol[1];
      const protocolquarterBelonging = protocol[2];
      const protocolTimeListPointer = protocol[3];
      const protocolPower = protocol[4];

      expect(protocolPrincipal).to.equal(ethers.utils.parseEther('5')); // All are vote state strategies
      expect(protocolTime).to.equal(executedAt2);
      expect(protocolquarterBelonging).to.equal(41);
      expect(protocolTimeListPointer).to.equal(4); // pid starting by zero, 5 strategies launched
      expect(protocolPower).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocolquarterBelonging);
      const quarterPrincipal = protocolQuarter[0];
      const quarterNumber = protocolQuarter[1];
      const quarterPower = protocolQuarter[2];
      const quarterSupply = protocolQuarter[3];

      expect(quarterPrincipal).to.equal(ethers.utils.parseEther('5'));
      expect(quarterNumber).to.equal(41);
      expect(quarterPower).to.equal(protocolPower);
      expect(quarterSupply).to.not.equal(0);

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract1, 42);
      await finishStrategy2Q(garden1, strategyContract2, 42);
      await finishStrategyQ1_noIncreaseTime(garden2, strategyContract3, 42);
      await finishStrategy2Q(garden2, strategyContract4, 42);
      await finishStrategy3Q(garden2, strategyContract5, 42);
      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract5,
      );

      // Protocol principal should be reduced accordingly
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      const protocolPrincipal2 = protocol2[0];
      const protocolTime2 = protocol2[1];
      const protocolquarterBelonging2 = protocol2[2];
      const protocolTimeListPointer2 = protocol2[3];
      const protocolPower2 = protocol2[4];

      expect(protocolPrincipal2).to.equal(ethers.utils.parseEther('0'));
      expect(protocolquarterBelonging2).to.equal(46);
      expect(protocolPower2).to.not.equal(0); // TODO CHECK EXACT AMOUNT
      expect(protocolTime2).to.equal(exitedAt3);
      expect(protocolTimeListPointer2).to.equal(9); // pid starting by zero, 9th checkpoint
      expect(protocolPower).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocolquarterBelonging2);
      const quarterPrincipal2 = protocolQuarter2[0];
      const quarterNumber2 = protocolQuarter2[1];
      const quarterPower2 = protocolQuarter2[2];
      const quarterSupply2 = protocolQuarter2[3];

      expect(quarterPrincipal2).to.equal(protocolPrincipal2); // All are voter strategies
      expect(quarterNumber2).to.equal(46);
      expect(quarterSupply2).to.equal(await rewardsDistributor.tokenSupplyPerQuarter(46));

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

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);

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

      // Protocol principal should be incremented accordingly
      const protocol = await rewardsDistributor.checkProtocol(executedAt2);
      const protocolPrincipal = protocol[0];
      const protocolTime = protocol[1];
      const protocolquarterBelonging = protocol[2];
      const protocolTimeListPointer = protocol[3];
      const protocolPower = protocol[4];

      expect(protocolPrincipal).to.equal(ethers.utils.parseEther('5')); // All are vote state strategies
      expect(protocolTime).to.equal(executedAt2);
      expect(protocolquarterBelonging).to.equal(1);
      expect(protocolTimeListPointer).to.equal(4); // pid starting by zero, 5 strategies launched
      expect(protocolPower).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocolquarterBelonging);
      const quarterPrincipal = protocolQuarter[0];
      const quarterNumber = protocolQuarter[1];
      const quarterPower = protocolQuarter[2];
      const quarterSupply = protocolQuarter[3];

      expect(quarterPrincipal).to.equal(ethers.utils.parseEther('5'));
      expect(quarterNumber).to.equal(1);
      expect(quarterPower).to.equal(protocolPower);
      expect(quarterSupply).to.not.equal(0);

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategyQ1_noIncreaseTime(garden1, strategyContract1, 42);
      await finishStrategy2Q(garden1, strategyContract2, 42);
      await finishStrategy2Y(garden2, strategyContract3, 42); // Increase time 2 years
      await finishStrategy2Q(garden2, strategyContract4, 42);
      await finishStrategy3Q(garden2, strategyContract5, 42);
      const [address3, active3, dataSet3, finalized3, executedAt3, exitedAt3] = await checkStrategyStateFinalized(
        strategyContract5,
      );

      // Protocol principal should be reduced accordingly
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      const protocolPrincipal2 = protocol2[0];
      const protocolTime2 = protocol2[1];
      const protocolquarterBelonging2 = protocol2[2];
      const protocolTimeListPointer2 = protocol2[3];
      const protocolPower2 = protocol2[4];

      expect(protocolPrincipal2).to.equal(ethers.utils.parseEther('0'));
      expect(protocolquarterBelonging2).to.equal(13);
      expect(protocolPower2).to.not.equal(0); // TODO CHECK EXACT AMOUNT
      expect(protocolTime2).to.equal(exitedAt3);
      expect(protocolTimeListPointer2).to.equal(9); // pid starting by zero, 9th checkpoint
      expect(protocolPower).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocolquarterBelonging2);
      const quarterPrincipal2 = protocolQuarter2[0];
      const quarterNumber2 = protocolQuarter2[1];
      const quarterPower2 = protocolQuarter2[2];
      const quarterSupply2 = protocolQuarter2[3];

      expect(quarterPrincipal2).to.equal(protocolPrincipal2); // All are voter strategies
      expect(quarterNumber2).to.equal(13);
      expect(quarterSupply2).to.equal(await rewardsDistributor.tokenSupplyPerQuarter(13));

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

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);

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

      // Protocol principal should be incremented accordingly
      const protocol = await rewardsDistributor.checkProtocol(executedAt2);
      const protocolPrincipal = protocol[0];
      const protocolTime = protocol[1];
      const protocolquarterBelonging = protocol[2];
      const protocolTimeListPointer = protocol[3];
      const protocolPower = protocol[4];

      expect(protocolPrincipal).to.equal(ethers.utils.parseEther('5')); // All are vote state strategies
      expect(protocolTime).to.equal(executedAt2);
      expect(protocolquarterBelonging).to.equal(1);
      expect(protocolTimeListPointer).to.equal(4); // pid starting by zero, 5 strategies launched
      expect(protocolPower).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocolquarterBelonging);
      const quarterPrincipal = protocolQuarter[0];
      const quarterNumber = protocolQuarter[1];
      const quarterPower = protocolQuarter[2];
      const quarterSupply = protocolQuarter[3];

      expect(quarterPrincipal).to.equal(ethers.utils.parseEther('5'));
      expect(quarterNumber).to.equal(1);
      expect(quarterPower).to.equal(protocolPower);
      expect(quarterSupply).to.not.equal(0);

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

      // Protocol principal should be reduced accordingly
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      const protocolPrincipal2 = protocol2[0];
      const protocolTime2 = protocol2[1];
      const protocolquarterBelonging2 = protocol2[2];
      const protocolTimeListPointer2 = protocol2[3];
      const protocolPower2 = protocol2[4];

      expect(protocolPrincipal2).to.equal(ethers.utils.parseEther('0'));
      expect(protocolquarterBelonging2).to.equal(13);
      expect(protocolPower2).to.not.equal(0); // TODO CHECK EXACT AMOUNT
      expect(protocolTime2).to.equal(exitedAt3);
      expect(protocolTimeListPointer2).to.equal(9); // pid starting by zero, 9th checkpoint
      expect(protocolPower).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocolquarterBelonging2);
      const quarterPrincipal2 = protocolQuarter2[0];
      const quarterNumber2 = protocolQuarter2[1];
      const quarterPower2 = protocolQuarter2[2];
      const quarterSupply2 = protocolQuarter2[3];

      expect(quarterPrincipal2).to.equal(protocolPrincipal2); // All are voter strategies
      expect(quarterNumber2).to.equal(13);
      expect(quarterSupply2).to.equal(await rewardsDistributor.tokenSupplyPerQuarter(13));

      const bablRewards1 = await strategyContract1.strategyRewards();
      const bablRewards2 = await strategyContract2.strategyRewards();
      const bablRewards3 = await strategyContract3.strategyRewards();
      const bablRewards4 = await strategyContract4.strategyRewards();
      const bablRewards5 = await strategyContract5.strategyRewards();
    });

    it('should claim Signer 1 its BABL rewards as contributor of 5 strategies (4 with positive profits) of 2 different Gardens with different timings along 3 Years', async function () {
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

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);

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

      // Protocol principal should be incremented accordingly
      const protocol = await rewardsDistributor.checkProtocol(executedAt2);
      const protocolPrincipal = protocol[0];
      const protocolTime = protocol[1];
      const protocolquarterBelonging = protocol[2];
      const protocolTimeListPointer = protocol[3];
      const protocolPower = protocol[4];

      expect(protocolPrincipal).to.equal(ethers.utils.parseEther('5')); // All are vote state strategies
      expect(protocolTime).to.equal(executedAt2);
      expect(protocolquarterBelonging).to.equal(1);
      expect(protocolTimeListPointer).to.equal(4); // pid starting by zero, 5 strategies launched
      expect(protocolPower).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter = await rewardsDistributor.checkQuarter(protocolquarterBelonging);
      const quarterPrincipal = protocolQuarter[0];
      const quarterNumber = protocolQuarter[1];
      const quarterPower = protocolQuarter[2];
      const quarterSupply = protocolQuarter[3];

      expect(quarterPrincipal).to.equal(ethers.utils.parseEther('5'));
      expect(quarterNumber).to.equal(1);
      expect(quarterPower).to.equal(protocolPower);
      expect(quarterSupply).to.not.equal(0);

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

      // Protocol principal should be reduced accordingly
      const protocol2 = await rewardsDistributor.checkProtocol(exitedAt3);
      const protocolPrincipal2 = protocol2[0];
      const protocolTime2 = protocol2[1];
      const protocolquarterBelonging2 = protocol2[2];
      const protocolTimeListPointer2 = protocol2[3];
      const protocolPower2 = protocol2[4];

      expect(protocolPrincipal2).to.equal(ethers.utils.parseEther('0'));
      expect(protocolquarterBelonging2).to.equal(13);
      expect(protocolPower2).to.not.equal(0); // TODO CHECK EXACT AMOUNT
      expect(protocolTime2).to.equal(exitedAt3);
      expect(protocolTimeListPointer2).to.equal(9); // pid starting by zero, 9th checkpoint
      expect(protocolPower).to.not.equal(0); // TODO Check exact numbers

      const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocolquarterBelonging2);
      const quarterPrincipal2 = protocolQuarter2[0];
      const quarterNumber2 = protocolQuarter2[1];
      const quarterPower2 = protocolQuarter2[2];
      const quarterSupply2 = protocolQuarter2[3];

      expect(quarterPrincipal2).to.equal(protocolPrincipal2); // All are voter strategies
      expect(quarterNumber2).to.equal(13);
      expect(quarterSupply2).to.equal(await rewardsDistributor.tokenSupplyPerQuarter(13));

      const bablRewards1 = await strategyContract1.strategyRewards();
      const bablRewards2 = await strategyContract2.strategyRewards();
      const bablRewards3 = await strategyContract3.strategyRewards();
      const bablRewards4 = await strategyContract4.strategyRewards();
      const bablRewards5 = await strategyContract5.strategyRewards();

      //await garden1.connect(signer1).claimReturns([strategyContract1, strategyContract2]);
      //await garden2.connect(signer1).claimReturns([strategyContract3, strategyContract4, strategyContract5]);
    });
  });
});
