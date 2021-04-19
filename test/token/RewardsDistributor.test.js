const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { ONE_DAY_IN_SECONDS, ONE_ETH, MINUS_ONE_ETH } = require('../../utils/constants');
const { increaseTime, from } = require('../utils/test-helpers');
const { loadFixture } = waffle;

const { createStrategy, executeStrategy, injectFakeProfits } = require('../fixtures/StrategyHelper.js');
const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require('../../utils/system.js');

const addresses = require('../../utils/addresses');
const { deployFolioFixture } = require('../fixtures/ControllerFixture');

async function finishStrategy(strategy, time = 0) {
  if (time > 0) {
    increaseTime(time);
  }
  await updateTWAPs(await strategy.garden());
  return strategy.finalizeStrategy(0, { gasPrice: 0 });
}

async function finishStrategyAfter30Days(strategy) {
  await finishStrategy(strategy, ONE_DAY_IN_SECONDS * 30);
}

async function finishStrategyAfterQuarter(strategy, fee = 0) {
  await finishStrategy(strategy, ONE_DAY_IN_SECONDS * 90);
}

async function finishStrategyAfter2Quarters(strategy, fee = 0) {
  await finishStrategy(strategy, ONE_DAY_IN_SECONDS * 180);
}

async function finishStrategyAfter2Years(strategy, fee = 0) {
  await finishStrategy(strategy, ONE_DAY_IN_SECONDS * 365 * 2);
}

async function getAndValidateProtocolTimestamp(rewardsDistributor, timestamp, protocolPerTimestamp) {
  const [principal, time, quarterBelonging, timeListPointer, power] = await rewardsDistributor.checkProtocol(timestamp);
  const obj = { principal, time, quarterBelonging, timeListPointer, power };

  expect(obj.principal).to.eq(protocolPerTimestamp.principal);
  expect(obj.time).to.eq(protocolPerTimestamp.time);
  expect(obj.quarterBelonging).to.eq(protocolPerTimestamp.quarterBelonging);
  expect(obj.timeListPointer).to.eq(protocolPerTimestamp.timeListPointer);
  // TODO: Check for power
  // expect(obj.power).to.eq(protocolPerTimestamp.power);

  return obj;
}

async function getAndValidateQuarter(rewardsDistributor, quarter, quarterObj) {
  const [quarterPrincipal, quarterNumber, quarterPower, supplyPerQuarter] = await rewardsDistributor.checkQuarter(
    quarter,
  );
  const obj = { quarterPrincipal, quarterNumber, quarterPower, supplyPerQuarter };

  expect(obj.quarterPrincipal).to.eq(quarterObj.quarterPrincipal);
  expect(obj.quarterNumber).to.eq(quarterObj.quarterNumber);
  // TODO: Check for power
  // expect(obj.quarterPower).to.eq(quarterObj.quarterPower);
  expect(obj.supplyPerQuarter).to.eq(quarterObj.supplyPerQuarter);

  return obj;
}

async function getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, timestamp, protocolObj) {
  await getAndValidateProtocolTimestamp(rewardsDistributor, timestamp, {
    principal: protocolObj.principal,
    time: timestamp,
    quarterBelonging: protocolObj.quarter,
    timeListPointer: protocolObj.timeListPointer,
    power: protocolObj.power,
  });

  await getAndValidateQuarter(rewardsDistributor, protocolObj.quarter, {
    quarterPrincipal: protocolObj.principal,
    quarterNumber: protocolObj.quarter,
    quarterPower: protocolObj.power,
    supplyPerQuarter: await rewardsDistributor.tokenSupplyPerQuarter(protocolObj.quarter),
  });
}

async function getStrategyState(strategy) {
  const [address, active, dataSet, finalized, executedAt, exitedAt, updatedAt] = await strategy.getStrategyState();

  return { address, active, dataSet, finalized, executedAt, exitedAt, updatedAt };
}

async function updateTWAPs(gardenAddress) {
  const garden = await ethers.getContractAt('Garden', gardenAddress);
  const controller = await ethers.getContractAt('BabController', await garden.controller());
  const priceOracle = await ethers.getContractAt('PriceOracle', await controller.priceOracle());
  const adapterAddress = (await priceOracle.getAdapters())[0];
  const adapter = await ethers.getContractAt('UniswapTWAP', adapterAddress);
  for (let i = 0; i < TWAP_ORACLE_GRANULARITY; i += 1) {
    await adapter.update(addresses.tokens.WETH, addresses.tokens.USDC);
    await adapter.update(addresses.tokens.WETH, addresses.tokens.DAI);
    increaseTime(TWAP_ORACLE_WINDOW / TWAP_ORACLE_GRANULARITY);
  }
}

describe.only('BABL Rewards Distributor', function () {
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let babController;
  let bablToken;
  let rewardsDistributor;
  let garden1;
  let garden2;
  let kyberTradeIntegration;
  let garden1LongStrategy1;
  let garden1LongStrategy2;
  let garden1LongStrategy3;
  let garden2LongStrategy1;
  let garden2LongStrategy2;
  let garden2LongStrategy3;

  async function createStrategies(strategies) {
    const retVal = [];
    for (let i = 0; i < strategies.length; i++) {
      const strategy = await createStrategy(
        'long',
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        strategies[i].garden,
      );
      retVal.push(strategy);
    }
    return retVal;
  }

  beforeEach(async () => {
    ({
      owner,
      signer1,
      signer2,
      signer3,
      garden1,
      garden2,
      babController,
      bablToken,
      rewardsDistributor,
      kyberTradeIntegration,
    } = await loadFixture(deployFolioFixture));

    garden1LongStrategy2 = await createStrategy(
      'long',
      'vote',
      [signer1, signer2, signer3],
      kyberTradeIntegration.address,
      garden1,
    );
    garden1LongStrategy3 = await createStrategy(
      'long',
      'vote',
      [signer1, signer2, signer3],
      kyberTradeIntegration.address,
      garden1,
    );
    garden2LongStrategy1 = await createStrategy(
      'long',
      'vote',
      [signer1, signer2, signer3],
      kyberTradeIntegration.address,
      garden2,
    );
    garden2LongStrategy2 = await createStrategy(
      'long',
      'vote',
      [signer1, signer2, signer3],
      kyberTradeIntegration.address,
      garden2,
    );
    garden2LongStrategy3 = await createStrategy(
      'long',
      'vote',
      [signer1, signer2, signer3],
      kyberTradeIntegration.address,
      garden2,
    );
  });

  describe('Deployment', function () {
    it('should successfully deploy BABL Mining Rewards Distributor contract', async function () {
      const deployedc = await rewardsDistributor.deployed(bablToken.address, babController.address);
      expect(!!deployedc).to.equal(true);
    });
  });

  describe('Strategy BABL Mining Rewards Calculation', async function () {
    it.only('should fail trying to calculate rewards of a strategy that has not ended yet', async function () {
      const [long] = await createStrategies([{ garden: garden1 }]);
      await executeStrategy(long, ONE_ETH);

      await expect(rewardsDistributor.getStrategyRewards(long.address)).to.be.revertedWith(
        'The strategy has to be finished',
      );
    });

    // TODO: This test doesn't check BABL rewards.
    it('should calculate correct BABL in case of 1 strategy with negative profit and total duration of 1 quarter', async function () {
      await executeStrategy(garden1LongStrategy1, ONE_ETH);

      const { updatedAt } = await getStrategyState(garden1LongStrategy1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: ONE_ETH,
        quarter: 1,
        timeListPointer: 0,
      });

      increaseTime(ONE_DAY_IN_SECONDS * 2);

      await finishStrategyAfter30Days(garden1LongStrategy1);

      const { exitedAt } = await getStrategyState(garden1LongStrategy1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 1,
        timeListPointer: 1,
      });

      await garden1LongStrategy1.strategyRewards();
    });

    // TODO: This test doesn't check BABL rewards.
    it('should calculate correct BABL in case of 1 strategy with positive profit and with total duration of 1 quarter', async function () {
      await executeStrategy(garden1LongStrategy1, ONE_ETH);

      await injectFakeProfits(garden1LongStrategy1, ONE_ETH.mul(222));

      increaseTime(ONE_DAY_IN_SECONDS * 2);

      await finishStrategyAfter30Days(garden1LongStrategy1);

      const { exitedAt } = await getStrategyState(garden1LongStrategy1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 1,
        timeListPointer: 1,
      });

      garden1LongStrategy1.strategyRewards();
    });

    // TODO: This test doesn't check BABL rewards.
    it.only('should calculate correct BABL in case of 2 strategies with total duration of 1 quarter', async function () {
      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await finishStrategyAfter30Days(long1);

      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: ONE_ETH.mul(2),
        quarter: 1,
        timeListPointer: 2,
      });

      await finishStrategyAfter30Days(long2);

      const { exitedAt: long2exitedAt } = await getStrategyState(long2);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, long2exitedAt, {
        principal: 0,
        quarter: 1,
        timeListPointer: 3,
      });

      await long1.strategyRewards();
      await long2.strategyRewards();
    });

    // TODO: This test doesn't check BABL rewards.
    it('should calculate correct BABL in case of 3 strategies with total duration of 1 quarter', async function () {
      await executeStrategy(garden1LongStrategy1, ONE_ETH);

      increaseTime(ONE_DAY_IN_SECONDS * 2);

      await executeStrategy(garden1LongStrategy2, ONE_ETH);
      await executeStrategy(garden1LongStrategy3, ONE_ETH);

      const { updatedAt } = await getStrategyState(garden1LongStrategy3);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: ONE_ETH.mul(3),
        quarter: 1,
        timeListPointer: 2,
      });

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      await finishStrategy(garden1LongStrategy1);
      await finishStrategy(garden1LongStrategy2);
      await finishStrategy(garden1LongStrategy3);

      const { exitedAt } = await getStrategyState(garden1LongStrategy3);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 1,
        timeListPointer: 5,
      });

      await garden1LongStrategy1.strategyRewards();
      await garden1LongStrategy2.strategyRewards();
      await garden1LongStrategy3.strategyRewards();
    });

    // TODO: This test doesn't check BABL rewards.
    it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with total duration of less than 1 quarter', async function () {
      await executeStrategy(garden1LongStrategy1, ONE_ETH);

      increaseTime(ONE_DAY_IN_SECONDS * 2);
      await executeStrategy(garden1LongStrategy2, ONE_ETH);
      await executeStrategy(garden2LongStrategy1, ONE_ETH);

      increaseTime(ONE_DAY_IN_SECONDS * 2);
      await executeStrategy(garden2LongStrategy2, ONE_ETH);
      await executeStrategy(garden2LongStrategy3, ONE_ETH);

      const { updatedAt } = await getStrategyState(garden2LongStrategy3);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: ONE_ETH.mul(5),
        quarter: 1,
        timeListPointer: 4,
      });

      increaseTime(ONE_DAY_IN_SECONDS * 30);
      await finishStrategy(garden1LongStrategy1);
      await finishStrategy(garden1LongStrategy2);
      await finishStrategy(garden2LongStrategy1);
      await finishStrategy(garden2LongStrategy2);
      await finishStrategy(garden2LongStrategy3);

      const { exitedAt } = await getStrategyState(garden2LongStrategy3);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 1,
        timeListPointer: 9,
      });

      await garden1LongStrategy1.strategyRewards();
      await garden1LongStrategy2.strategyRewards();
      await garden2LongStrategy1.strategyRewards();
      await garden2LongStrategy2.strategyRewards();
      await garden2LongStrategy3.strategyRewards();
    });

    // TODO: This test doesn't check BABL rewards.
    it('should calculate correct BABL in case of 1 strategy with total duration of 2 quarters', async function () {
      await executeStrategy(garden1LongStrategy1, ONE_ETH);

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      await finishStrategyAfter2Quarters(garden1LongStrategy1);
      const { exitedAt } = await getStrategyState(garden1LongStrategy1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 3,
        timeListPointer: 1,
      });

      await garden1LongStrategy1.strategyRewards();
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

      const [address, active, dataSet, finalized, executedAt, exitedAt, updatedAt] = await checkStrategyExecuted(
        strategyContract1,
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      await finishStrategy2Q(garden1, strategyContract1, 42);

      const [
        address3,
        active3,
        dataSet3,
        finalized3,
        executedAt3,
        exitedAt3,
        updatedAt3,
      ] = await checkStrategyFinalized(strategyContract1);

      // Check protocol
      const protocol2 = await rewardsDistributor.checkProtocol(updatedAt3);
      await checkProtocolTimestamp(protocol2, ethers.utils.parseEther('0'), exitedAt3, 42, 2, protocol2[4]); // TODO CHECK EXACT AMOUNT
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

    // it('should calculate correct BABL rewards in case of 1 strategy with total duration of 3 quarters', async function () {
    //   // Create strategy 1

    //   const strategyContract1 = await createStrategy(
    //     0,
    //     'active',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden1,
    //   );

    //   // Execute strategy 1
    //   await executeStrategy(garden1, strategyContract1, ethers.utils.parseEther('1'), 42); // Strategy 1

    //   const [address, active, dataSet, finalized, executedAt, exitedAt, updatedAt] = await checkStrategyExecuted(
    //     strategyContract1,
    //   );
    //   // Check protocol
    //   const protocol = await rewardsDistributor.checkProtocol(updatedAt);
    //   await checkProtocolTimestamp(protocol, ethers.utils.parseEther('2'), updatedAt, 1, 1, protocol[4]);
    //   // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

    //   const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
    //   const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
    //   await checkQuarterWithParams(
    //     quarterPrincipal,
    //     quarterNumber,
    //     quarterPower,
    //     quarterSupply,
    //     ethers.utils.parseEther('2'),
    //     1,
    //     protocol[4],
    //     await rewardsDistributor.tokenSupplyPerQuarter(1),
    //   );
    //   // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

    //   ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

    //   await finishStrategy3Q(garden1, strategyContract1, 42);

    //   const [
    //     address3,
    //     active3,
    //     dataSet3,
    //     finalized3,
    //     executedAt3,
    //     exitedAt3,
    //     updatedAt3,
    //   ] = await checkStrategyFinalized(strategyContract1);

    //   // Check protocol
    //   const protocol2 = await rewardsDistributor.checkProtocol(updatedAt3);
    //   await checkProtocolTimestamp(protocol2, ethers.utils.parseEther('0'), exitedAt3, 3, 2, protocol2[4]); // TODO CHECK EXACT AMOUNT
    //   // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

    //   expect(protocol2[4]).to.not.equal(0); // TODO Check exact numbers

    //   const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
    //   const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
    //   await checkQuarterWithParams(
    //     quarterPrincipal2,
    //     quarterNumber2,
    //     quarterPower2,
    //     quarterSupply2,
    //     protocol2[0],
    //     3,
    //     quarterPower2,
    //     await rewardsDistributor.tokenSupplyPerQuarter(3),
    //   );
    //   // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

    //   expect(protocol2[4]).to.gt(quarterPower2);

    //   expect(quarterPrincipal2).to.equal(protocol2[0]); // All are voter strategies

    //   const bablRewards1 = await strategyContract1.strategyRewards();
    // });

    // it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with different timings along 3 quarters', async function () {
    //   // Create strategy 1

    //   const strategyContract1 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden1,
    //   );

    //   // Create strategy 2

    //   const strategyContract2 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden1,
    //   );

    //   // Create strategy 3

    //   const strategyContract3 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden2,
    //   );

    //   // Create strategy 4

    //   const strategyContract4 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden2,
    //   );
    //   // Create strategy 5

    //   const strategyContract5 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden2,
    //   );
    //   // Execute strategy 1
    //   await executeStrategy(garden1, strategyContract1, ethers.utils.parseEther('1'), 42); // Strategy 1

    //   const [address, active, dataSet, finalized, executedAt, exitedAt, updatedAt] = await checkStrategyExecuted(
    //     strategyContract1,
    //   );

    //   ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
    //   // Execute strategy 2
    //   await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('1'), 42); // Strategy 2
    //   // Execute strategy 3
    //   await executeStrategy(garden2, strategyContract3, ethers.utils.parseEther('1'), 42); // Strategy 3

    //   ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
    //   // Execute strategy 4
    //   await executeStrategy(garden2, strategyContract4, ethers.utils.parseEther('1'), 42); // Strategy 4
    //   // Execute strategy 5
    //   await executeStrategy(garden2, strategyContract5, ethers.utils.parseEther('1'), 42); // Strategy 5

    //   const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2, updatedAt2] = await checkStrategyExecuted(
    //     strategyContract5,
    //   );

    //   // Check protocol
    //   const protocol = await rewardsDistributor.checkProtocol(updatedAt2);
    //   await checkProtocolTimestamp(protocol, ethers.utils.parseEther('5'), executedAt2, 1, 4, protocol[4]);
    //   // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

    //   const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
    //   const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
    //   await checkQuarterWithParams(
    //     quarterPrincipal,
    //     quarterNumber,
    //     quarterPower,
    //     quarterSupply,
    //     ethers.utils.parseEther('5'),
    //     1,
    //     protocol[4],
    //     await rewardsDistributor.tokenSupplyPerQuarter(1),
    //   );
    //   // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

    //   ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

    //   await finishStrategyQ1NoIncreaseTime(garden1, strategyContract1, 42);
    //   await finishStrategy2Q(garden1, strategyContract2, 42);
    //   await finishStrategyQ1NoIncreaseTime(garden2, strategyContract3, 42);
    //   await finishStrategy2Q(garden2, strategyContract4, 42);
    //   await finishStrategy3Q(garden2, strategyContract5, 42);
    //   const [
    //     address3,
    //     active3,
    //     dataSet3,
    //     finalized3,
    //     executedAt3,
    //     exitedAt3,
    //     updatedAt3,
    //   ] = await checkStrategyFinalized(strategyContract5);

    //   // Check protocol
    //   const protocol2 = await rewardsDistributor.checkProtocol(updatedAt3);
    //   await checkProtocolTimestamp(protocol2, ethers.utils.parseEther('0'), exitedAt3, 5, 9, protocol2[4]); // TODO CHECK EXACT AMOUNT
    //   // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

    //   const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
    //   const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
    //   await checkQuarterWithParams(
    //     quarterPrincipal2,
    //     quarterNumber2,
    //     quarterPower2,
    //     quarterSupply2,
    //     protocol2[0],
    //     5,
    //     quarterPower2,
    //     await rewardsDistributor.tokenSupplyPerQuarter(5),
    //   );
    //   // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

    //   const bablRewards1 = await strategyContract1.strategyRewards();
    //   const bablRewards2 = await strategyContract2.strategyRewards();
    //   const bablRewards3 = await strategyContract3.strategyRewards();
    //   const bablRewards4 = await strategyContract4.strategyRewards();
    //   const bablRewards5 = await strategyContract5.strategyRewards();
    // });

    // it('should calculate correct BABL (in 10 Years from now) in case of 5 strategies of 2 different Gardens with different timings along 3 quarters', async function () {
    //   ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 3650]);

    //   // Create strategy 1

    //   const strategyContract1 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden1,
    //   );

    //   // Create strategy 2

    //   const strategyContract2 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden1,
    //   );

    //   // Create strategy 3

    //   const strategyContract3 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden2,
    //   );

    //   // Create strategy 4

    //   const strategyContract4 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden2,
    //   );
    //   // Create strategy 5

    //   const strategyContract5 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden2,
    //   );
    //   // Execute strategy 1
    //   await executeStrategy(garden1, strategyContract1, ethers.utils.parseEther('1'), 42); // Strategy 1

    //   const [address, active, dataSet, finalized, executedAt, exitedAt, updatedAt] = await checkStrategyExecuted(
    //     strategyContract1,
    //   );

    //   ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
    //   // Execute strategy 2
    //   await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('1'), 42); // Strategy 2
    //   // Execute strategy 3
    //   await executeStrategy(garden2, strategyContract3, ethers.utils.parseEther('1'), 42); // Strategy 3

    //   ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
    //   // Execute strategy 4
    //   await executeStrategy(garden2, strategyContract4, ethers.utils.parseEther('1'), 42); // Strategy 4
    //   // Execute strategy 5
    //   await executeStrategy(garden2, strategyContract5, ethers.utils.parseEther('1'), 42); // Strategy 5

    //   const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2, updatedAt2] = await checkStrategyExecuted(
    //     strategyContract5,
    //   );
    //   // Check protocol
    //   const protocol = await rewardsDistributor.checkProtocol(updatedAt2);
    //   await checkProtocolTimestamp(protocol, ethers.utils.parseEther('5'), executedAt2, 41, 4, protocol[4]);
    //   // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

    //   const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
    //   const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
    //   await checkQuarterWithParams(
    //     quarterPrincipal,
    //     quarterNumber,
    //     quarterPower,
    //     quarterSupply,
    //     ethers.utils.parseEther('5'),
    //     41,
    //     protocol[4],
    //     await rewardsDistributor.tokenSupplyPerQuarter(41),
    //   );
    //   // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

    //   ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

    //   await finishStrategyQ1NoIncreaseTime(garden1, strategyContract1, 42);
    //   await finishStrategy2Q(garden1, strategyContract2, 42);
    //   await finishStrategyQ1NoIncreaseTime(garden2, strategyContract3, 42);
    //   await finishStrategy2Q(garden2, strategyContract4, 42);
    //   await finishStrategy3Q(garden2, strategyContract5, 42);
    //   const [
    //     address3,
    //     active3,
    //     dataSet3,
    //     finalized3,
    //     executedAt3,
    //     exitedAt3,
    //     updatedAt3,
    //   ] = await checkStrategyFinalized(strategyContract5);

    //   // Check protocol
    //   const protocol2 = await rewardsDistributor.checkProtocol(updatedAt3);
    //   await checkProtocolTimestamp(protocol2, ethers.utils.parseEther('0'), exitedAt3, 46, 9, protocol2[4]); // TODO CHECK EXACT AMOUNT
    //   // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

    //   const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
    //   const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
    //   await checkQuarterWithParams(
    //     quarterPrincipal2,
    //     quarterNumber2,
    //     quarterPower2,
    //     quarterSupply2,
    //     protocol2[0],
    //     46,
    //     quarterPower2,
    //     await rewardsDistributor.tokenSupplyPerQuarter(46),
    //   );
    //   // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

    //   expect(quarterPrincipal2).to.equal(protocol2[0]);

    //   const bablRewards1 = await strategyContract1.strategyRewards();
    //   const bablRewards2 = await strategyContract2.strategyRewards();
    //   const bablRewards3 = await strategyContract3.strategyRewards();
    //   const bablRewards4 = await strategyContract4.strategyRewards();
    //   const bablRewards5 = await strategyContract5.strategyRewards();
    // });

    // it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with different timings along 3 Years', async function () {
    //   // Create strategy 1

    //   const strategyContract1 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden1,
    //   );

    //   // Create strategy 2

    //   const strategyContract2 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden1,
    //   );

    //   // Create strategy 3

    //   const strategyContract3 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden2,
    //   );

    //   // Create strategy 4

    //   const strategyContract4 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden2,
    //   );
    //   // Create strategy 5

    //   const strategyContract5 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden2,
    //   );
    //   // Execute strategy 1
    //   await executeStrategy(garden1, strategyContract1, ethers.utils.parseEther('1'), 42); // Strategy 1

    //   const [address, active, dataSet, finalized, executedAt, exitedAt, updatedAt] = await checkStrategyExecuted(
    //     strategyContract1,
    //   );

    //   ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
    //   // Execute strategy 2
    //   await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('1'), 42); // Strategy 2
    //   // Execute strategy 3
    //   await executeStrategy(garden2, strategyContract3, ethers.utils.parseEther('1'), 42); // Strategy 3

    //   ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
    //   // Execute strategy 4
    //   await executeStrategy(garden2, strategyContract4, ethers.utils.parseEther('1'), 42); // Strategy 4
    //   // Execute strategy 5
    //   await executeStrategy(garden2, strategyContract5, ethers.utils.parseEther('1'), 42); // Strategy 5

    //   const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2, updatedAt2] = await checkStrategyExecuted(
    //     strategyContract5,
    //   );

    //   // Check protocol
    //   const protocol = await rewardsDistributor.checkProtocol(updatedAt2);
    //   await checkProtocolTimestamp(protocol, ethers.utils.parseEther('5'), executedAt2, 1, 4, protocol[4]);
    //   // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

    //   const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
    //   const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
    //   await checkQuarterWithParams(
    //     quarterPrincipal,
    //     quarterNumber,
    //     quarterPower,
    //     quarterSupply,
    //     ethers.utils.parseEther('5'),
    //     1,
    //     protocol[4],
    //     await rewardsDistributor.tokenSupplyPerQuarter(1),
    //   );
    //   // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

    //   ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

    //   await finishStrategyQ1NoIncreaseTime(garden1, strategyContract1, 42);
    //   await finishStrategy2Q(garden1, strategyContract2, 42);
    //   await finishStrategy2Y(garden2, strategyContract3, 42); // Increase time 2 years
    //   await finishStrategy2Q(garden2, strategyContract4, 42);
    //   await finishStrategy3Q(garden2, strategyContract5, 42);
    //   const [
    //     address3,
    //     active3,
    //     dataSet3,
    //     finalized3,
    //     executedAt3,
    //     exitedAt3,
    //     updatedAt3,
    //   ] = await checkStrategyFinalized(strategyContract5);

    //   // Check protocol
    //   const protocol2 = await rewardsDistributor.checkProtocol(updatedAt3);
    //   await checkProtocolTimestamp(protocol2, ethers.utils.parseEther('0'), exitedAt3, 13, 9, protocol2[4]); // TODO CHECK EXACT AMOUNT
    //   // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

    //   const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
    //   const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
    //   await checkQuarterWithParams(
    //     quarterPrincipal2,
    //     quarterNumber2,
    //     quarterPower2,
    //     quarterSupply2,
    //     protocol2[0],
    //     13,
    //     quarterPower2,
    //     await rewardsDistributor.tokenSupplyPerQuarter(13),
    //   );
    //   // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

    //   expect(quarterPrincipal2).to.equal(protocol2[0]);

    //   const bablRewards1 = await strategyContract1.strategyRewards();
    //   const bablRewards2 = await strategyContract2.strategyRewards();
    //   const bablRewards3 = await strategyContract3.strategyRewards();
    //   const bablRewards4 = await strategyContract4.strategyRewards();
    //   const bablRewards5 = await strategyContract5.strategyRewards();
    // });

    // it('should calculate correct BABL in case of 5 (4 with positive profits) strategies of 2 different Gardens with different timings along 3 Years', async function () {
    //   // Create strategy 1

    //   const strategyContract1 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden1,
    //   );

    //   // Create strategy 2

    //   const strategyContract2 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden1,
    //   );

    //   // Create strategy 3

    //   const strategyContract3 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden2,
    //   );

    //   // Create strategy 4

    //   const strategyContract4 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden2,
    //   );
    //   // Create strategy 5

    //   const strategyContract5 = await createStrategy(
    //     0,
    //     'vote',
    //     [signer1, signer2, signer3],
    //     kyberTradeIntegration.address,
    //     garden2,
    //   );
    //   // Execute strategy 1
    //   await executeStrategy(garden1, strategyContract1, ethers.utils.parseEther('1'), 42); // Strategy 1

    //   const [address, active, dataSet, finalized, executedAt, exitedAt, updatedAt] = await checkStrategyExecuted(
    //     strategyContract1,
    //   );

    //   ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
    //   // Execute strategy 2
    //   await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('1'), 42); // Strategy 2
    //   // Execute strategy 3
    //   await executeStrategy(garden2, strategyContract3, ethers.utils.parseEther('1'), 42); // Strategy 3

    //   ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
    //   // Execute strategy 4
    //   await executeStrategy(garden2, strategyContract4, ethers.utils.parseEther('1'), 42); // Strategy 4
    //   // Execute strategy 5
    //   await executeStrategy(garden2, strategyContract5, ethers.utils.parseEther('1'), 42); // Strategy 5

    //   const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2, updatedAt2] = await checkStrategyExecuted(
    //     strategyContract5,
    //   );

    //   // Check protocol
    //   const protocol = await rewardsDistributor.checkProtocol(updatedAt2);
    //   await checkProtocolTimestamp(protocol, ethers.utils.parseEther('5'), executedAt2, 1, 4, protocol[4]);
    //   // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

    //   const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
    //   const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
    //   await checkQuarterWithParams(
    //     quarterPrincipal,
    //     quarterNumber,
    //     quarterPower,
    //     quarterSupply,
    //     ethers.utils.parseEther('5'),
    //     1,
    //     protocol[4],
    //     await rewardsDistributor.tokenSupplyPerQuarter(1),
    //   );
    //   // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

    //   ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

    //   await injectFakeProfits(strategyContract1, ethers.utils.parseEther('200'));
    //   await finishStrategyQ1NoIncreaseTime(garden1, strategyContract1, 42);

    //   await finishStrategy2Q(garden1, strategyContract2, 42);

    //   await injectFakeProfits(strategyContract3, ethers.utils.parseEther('200'));
    //   await finishStrategy2Y(garden2, strategyContract3, 42); // Increase time 2 years

    //   await injectFakeProfits(strategyContract4, ethers.utils.parseEther('222'));
    //   await finishStrategy2Q(garden2, strategyContract4, 42);

    //   await injectFakeProfits(strategyContract5, ethers.utils.parseEther('222'));
    //   await finishStrategy3Q(garden2, strategyContract5, 42);
    //   const [
    //     address3,
    //     active3,
    //     dataSet3,
    //     finalized3,
    //     executedAt3,
    //     exitedAt3,
    //     updatedAt3,
    //   ] = await checkStrategyFinalized(strategyContract5);

    //   // Check protocol
    //   const protocol2 = await rewardsDistributor.checkProtocol(updatedAt3);
    //   await checkProtocolTimestamp(protocol2, ethers.utils.parseEther('0'), exitedAt3, 13, 9, protocol2[4]); // TODO CHECK EXACT AMOUNT
    //   // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

    //   const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
    //   const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
    //   await checkQuarterWithParams(
    //     quarterPrincipal2,
    //     quarterNumber2,
    //     quarterPower2,
    //     quarterSupply2,
    //     protocol2[0],
    //     13,
    //     quarterPower2,
    //     await rewardsDistributor.tokenSupplyPerQuarter(13),
    //   );
    //   // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

    //   const bablRewards1 = await strategyContract1.strategyRewards();
    //   const bablRewards2 = await strategyContract2.strategyRewards();
    //   const bablRewards3 = await strategyContract3.strategyRewards();
    //   const bablRewards4 = await strategyContract4.strategyRewards();
    //   const bablRewards5 = await strategyContract5.strategyRewards();
    // });

    // describe('Claiming Profits and BABL Rewards', function () {
    //   it('should claim and update balances of Signer 1 either Garden tokens or BABL rewards as contributor of 2 strategies (1 with positive profits and other without them) within a quarter', async function () {
    //     // Create strategy 1

    //     const strategyContract = await createStrategy(
    //       0,
    //       'vote',
    //       [signer1, signer2, signer3],
    //       kyberTradeIntegration.address,
    //       garden1,
    //     );

    //     // Create strategy 2

    //     const strategyContract2 = await createStrategy(
    //       0,
    //       'vote',
    //       [signer1, signer2, signer3],
    //       kyberTradeIntegration.address,
    //       garden1,
    //     );

    //     // Execute strategy 1
    //     await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42); // Strategy 1

    //     const [address, active, dataSet, finalized, executedAt, exitedAt, updatedAt] = await checkStrategyExecuted(
    //       strategyContract,
    //     );

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

    //     // Execute strategy 2, 2 days later

    //     await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('2'), 42); // Strategy 2

    //     const [
    //       address2,
    //       active2,
    //       dataSet2,
    //       finalized2,
    //       executedAt2,
    //       exitedAt2,
    //       updatedAt2,
    //     ] = await checkStrategyExecuted(strategyContract2);

    //     // Check protocol
    //     const protocol = await rewardsDistributor.checkProtocol(updatedAt2);
    //     await checkProtocolTimestamp(protocol, ethers.utils.parseEther('3'), executedAt2, 1, 1, protocol[4]);

    //     const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
    //     const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
    //     await checkQuarterWithParams(
    //       quarterPrincipal,
    //       quarterNumber,
    //       quarterPower,
    //       quarterSupply,
    //       ethers.utils.parseEther('3'),
    //       1,
    //       protocol[4],
    //       await rewardsDistributor.tokenSupplyPerQuarter(1),
    //     );

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

    //     await injectFakeProfits(strategyContract, ethers.utils.parseEther('200'));
    //     await finishStrategyQ1(garden1, strategyContract, 42);

    //     const [
    //       address3,
    //       active3,
    //       dataSet3,
    //       finalized3,
    //       executedAt3,
    //       exitedAt3,
    //       updatedAt3,
    //     ] = await checkStrategyFinalized(strategyContract);

    //     // Check protocol
    //     const protocol2 = await rewardsDistributor.checkProtocol(updatedAt3);
    //     await checkProtocolTimestamp(protocol2, ethers.utils.parseEther('2'), exitedAt3, 1, 2, protocol2[4]); // TODO CHECK EXACT AMOUNT

    //     expect(protocol2[4]).to.not.equal(0); // TODO Check exact numbers

    //     const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
    //     const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
    //     await checkQuarterWithParams(
    //       quarterPrincipal2,
    //       quarterNumber2,
    //       quarterPower2,
    //       quarterSupply2,
    //       protocol2[0],
    //       1,
    //       protocol2[4],
    //       await rewardsDistributor.tokenSupplyPerQuarter(1),
    //     );

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

    //     await finishStrategyQ1(garden1, strategyContract2, 42);
    //     const [address4, active4, dataSet4, finalized4, executedAt4, exitedAt4] = await checkStrategyFinalized(
    //       strategyContract2,
    //     );

    //     // Check protocol
    //     const protocol3 = await rewardsDistributor.checkProtocol(exitedAt4);
    //     await checkProtocolTimestamp(protocol3, ethers.utils.parseEther('0'), exitedAt4, 1, 3, protocol3[4]); // TODO CHECK EXACT AMOUNT

    //     expect(protocol3[4]).to.not.equal(0); // TODO CHECK EXACT AMOUNT

    //     const protocolQuarter3 = await rewardsDistributor.checkQuarter(protocol3[2]);
    //     const [quarterPrincipal3, quarterNumber3, quarterPower3, quarterSupply3] = protocolQuarter3;
    //     await checkQuarterWithParams(
    //       quarterPrincipal3,
    //       quarterNumber3,
    //       quarterPower3,
    //       quarterSupply3,
    //       protocol3[0],
    //       1,
    //       protocol3[4],
    //       await rewardsDistributor.tokenSupplyPerQuarter(1),
    //     );

    //     const bablRewards1 = await strategyContract.strategyRewards();
    //     const bablRewards2 = await strategyContract2.strategyRewards();

    //     // Transfer 500_000e18 tokens from owner to rewardsDistributor for BABL Mining Program
    //     const value = ethers.utils.parseEther('500000');
    //     await bablToken.connect(owner).transfer(rewardsDistributor.address, value);

    //     // Check Balances
    //     const ownerBalance = await bablToken.balanceOf(owner.address);
    //     const signer1Balance = await bablToken.balanceOf(signer1.address);

    //     const rewardsDistributorBalance = await bablToken.balanceOf(rewardsDistributor.address);

    //     expect(await bablToken.totalSupply()).to.equal(BigInt(ownerBalance) + BigInt(rewardsDistributorBalance));

    //     const signer1Balance0 = await bablToken.balanceOf(signer1.address);
    //     const signer1Profit0 = await garden1.balanceOf(signer1.address);
    //     // We claim our tokens and check that they are received properly
    //     await garden1.connect(signer1).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const signer1Balance1 = await bablToken.balanceOf(signer1.address);
    //     const signer1Profit1 = await garden1.balanceOf(signer1.address);

    //     expect(signer1Balance1.toString()).to.gt(ethers.utils.parseEther('29000'));
    //     expect(signer1Profit1.toString()).to.gt(ethers.utils.parseEther('2'));
    //   });
    //   it('should not allow a race condition of two consecutive claims for the same rewards & profit of the same strategies', async function () {
    //     // Create strategy 1

    //     const strategyContract = await createStrategy(
    //       0,
    //       'vote',
    //       [signer1, signer2, signer3],
    //       kyberTradeIntegration.address,
    //       garden1,
    //     );

    //     // Create strategy 2

    //     const strategyContract2 = await createStrategy(
    //       0,
    //       'vote',
    //       [signer1, signer2, signer3],
    //       kyberTradeIntegration.address,
    //       garden1,
    //     );

    //     // Execute strategy 1
    //     await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42); // Strategy 1

    //     const [address, active, dataSet, finalized, executedAt, exitedAt, updatedAt] = await checkStrategyExecuted(
    //       strategyContract,
    //     );

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

    //     // Execute strategy 2, 2 days later

    //     await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('2'), 42); // Strategy 2

    //     const [
    //       address2,
    //       active2,
    //       dataSet2,
    //       finalized2,
    //       executedAt2,
    //       exitedAt2,
    //       updatedAt2,
    //     ] = await checkStrategyExecuted(strategyContract2);

    //     // Check protocol
    //     const protocol = await rewardsDistributor.checkProtocol(updatedAt2);
    //     await checkProtocolTimestamp(protocol, ethers.utils.parseEther('3'), executedAt2, 1, 1, protocol[4]);

    //     const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
    //     const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
    //     await checkQuarterWithParams(
    //       quarterPrincipal,
    //       quarterNumber,
    //       quarterPower,
    //       quarterSupply,
    //       ethers.utils.parseEther('3'),
    //       1,
    //       protocol[4],
    //       await rewardsDistributor.tokenSupplyPerQuarter(1),
    //     );

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

    //     await injectFakeProfits(strategyContract, ethers.utils.parseEther('200'));
    //     await finishStrategyQ1(garden1, strategyContract, 42);

    //     const [
    //       address3,
    //       active3,
    //       dataSet3,
    //       finalized3,
    //       executedAt3,
    //       exitedAt3,
    //       updatedAt3,
    //     ] = await checkStrategyFinalized(strategyContract);

    //     // Check protocol
    //     const protocol2 = await rewardsDistributor.checkProtocol(updatedAt3);
    //     await checkProtocolTimestamp(protocol2, ethers.utils.parseEther('2'), exitedAt3, 1, 2, protocol2[4]); // TODO CHECK EXACT AMOUNT

    //     expect(protocol2[4]).to.not.equal(0); // TODO Check exact numbers

    //     const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
    //     const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
    //     await checkQuarterWithParams(
    //       quarterPrincipal2,
    //       quarterNumber2,
    //       quarterPower2,
    //       quarterSupply2,
    //       protocol2[0],
    //       1,
    //       protocol2[4],
    //       await rewardsDistributor.tokenSupplyPerQuarter(1),
    //     );

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

    //     await finishStrategyQ1(garden1, strategyContract2, 42);
    //     const [address4, active4, dataSet4, finalized4, executedAt4, exitedAt4] = await checkStrategyFinalized(
    //       strategyContract2,
    //     );

    //     // Check protocol
    //     const protocol3 = await rewardsDistributor.checkProtocol(exitedAt4);
    //     await checkProtocolTimestamp(protocol3, ethers.utils.parseEther('0'), exitedAt4, 1, 3, protocol3[4]); // TODO CHECK EXACT AMOUNT

    //     expect(protocol3[4]).to.not.equal(0); // TODO CHECK EXACT AMOUNT

    //     const protocolQuarter3 = await rewardsDistributor.checkQuarter(protocol3[2]);
    //     const [quarterPrincipal3, quarterNumber3, quarterPower3, quarterSupply3] = protocolQuarter3;
    //     await checkQuarterWithParams(
    //       quarterPrincipal3,
    //       quarterNumber3,
    //       quarterPower3,
    //       quarterSupply3,
    //       protocol3[0],
    //       1,
    //       protocol3[4],
    //       await rewardsDistributor.tokenSupplyPerQuarter(1),
    //     );

    //     // Transfer 500_000e18 tokens from owner to rewardsDistributor for BABL Mining Program
    //     const value = ethers.utils.parseEther('500000');
    //     await bablToken.connect(owner).transfer(rewardsDistributor.address, value);

    //     // Check Balances
    //     const ownerBalance = await bablToken.balanceOf(owner.address);
    //     const rewardsDistributorBalance = await bablToken.balanceOf(rewardsDistributor.address);

    //     expect(await bablToken.totalSupply()).to.equal(BigInt(ownerBalance) + BigInt(rewardsDistributorBalance));

    //     // Signer 1 claim its tokens and check that they are received properly
    //     await garden1.connect(signer1).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor = await garden1.getContributor(signer1.address);
    //     // Try again to claim the same tokens but no more tokens are delivered
    //     await garden1.connect(signer1).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor2 = await garden1.getContributor(signer1.address);
    //     await expect(contributor2[4].toString()).to.equal(contributor[4]);

    //     // Signer 2 claim his tokens and check that they are received properly
    //     await garden1.connect(signer2).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor3 = await garden1.getContributor(signer2.address);
    //     // Try again to claim the same tokens but no more tokens are delivered
    //     await garden1.connect(signer2).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor4 = await garden1.getContributor(signer2.address);
    //     await expect(contributor4[4].toString()).to.equal(contributor3[4]);
    //   });

    //   it('should only provide new additional BABL and profits between claims (claiming results of 2 strategies only 1 with profit)', async function () {
    //     // Create strategy 1

    //     const strategyContract = await createStrategy(
    //       0,
    //       'vote',
    //       [signer1, signer2, signer3],
    //       kyberTradeIntegration.address,
    //       garden1,
    //     );

    //     // Create strategy 2

    //     const strategyContract2 = await createStrategy(
    //       0,
    //       'vote',
    //       [signer1, signer2, signer3],
    //       kyberTradeIntegration.address,
    //       garden1,
    //     );

    //     // Execute strategy 1
    //     await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42); // Strategy 1

    //     const [address, active, dataSet, finalized, executedAt, exitedAt, updatedAt] = await checkStrategyExecuted(
    //       strategyContract,
    //     );

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

    //     // Execute strategy 2, 2 days later

    //     await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('2'), 42); // Strategy 2

    //     const [
    //       address2,
    //       active2,
    //       dataSet2,
    //       finalized2,
    //       executedAt2,
    //       exitedAt2,
    //       updatedAt2,
    //     ] = await checkStrategyExecuted(strategyContract2);

    //     // Check protocol
    //     const protocol = await rewardsDistributor.checkProtocol(updatedAt2);
    //     await checkProtocolTimestamp(protocol, ethers.utils.parseEther('3'), executedAt2, 1, 1, protocol[4]);

    //     const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
    //     const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
    //     await checkQuarterWithParams(
    //       quarterPrincipal,
    //       quarterNumber,
    //       quarterPower,
    //       quarterSupply,
    //       ethers.utils.parseEther('3'),
    //       1,
    //       protocol[4],
    //       await rewardsDistributor.tokenSupplyPerQuarter(1),
    //     );

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

    //     await injectFakeProfits(strategyContract, ethers.utils.parseEther('200'));
    //     await finishStrategyQ1(garden1, strategyContract, 42);

    //     const [
    //       address3,
    //       active3,
    //       dataSet3,
    //       finalized3,
    //       executedAt3,
    //       exitedAt3,
    //       updatedAt3,
    //     ] = await checkStrategyFinalized(strategyContract);

    //     // Check protocol
    //     const protocol2 = await rewardsDistributor.checkProtocol(updatedAt3);
    //     await checkProtocolTimestamp(protocol2, ethers.utils.parseEther('2'), exitedAt3, 1, 2, protocol2[4]); // TODO CHECK EXACT AMOUNT

    //     expect(protocol2[4]).to.not.equal(0); // TODO Check exact numbers

    //     const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
    //     const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
    //     await checkQuarterWithParams(
    //       quarterPrincipal2,
    //       quarterNumber2,
    //       quarterPower2,
    //       quarterSupply2,
    //       protocol2[0],
    //       1,
    //       protocol2[4],
    //       await rewardsDistributor.tokenSupplyPerQuarter(1),
    //     );

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

    //     const bablRewards1 = await strategyContract.strategyRewards();
    //     const bablRewards2 = await strategyContract2.strategyRewards();

    //     // Transfer 500_000e18 tokens from owner to rewardsDistributor for BABL Mining Program
    //     const value = ethers.utils.parseEther('500000');
    //     await bablToken.connect(owner).transfer(rewardsDistributor.address, value);

    //     // Check Balances
    //     const ownerBalance = await bablToken.balanceOf(owner.address);
    //     const rewardsDistributorBalance = await bablToken.balanceOf(rewardsDistributor.address);

    //     expect(await bablToken.totalSupply()).to.equal(BigInt(ownerBalance) + BigInt(rewardsDistributorBalance));

    //     // Signer 1 claim its tokens and check that they are received properly
    //     await garden1.connect(signer1).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor = await garden1.getContributor(signer1.address);
    //     // Try again to claim the same tokens but no more tokens are delivered
    //     await garden1.connect(signer1).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor2 = await garden1.getContributor(signer1.address);
    //     await expect(contributor2[4].toString()).to.equal(contributor[4]);

    //     // Signer 2 claim his tokens and check that they are received properly
    //     await garden1.connect(signer2).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor3 = await garden1.getContributor(signer2.address);
    //     // Try again to claim the same tokens but no more tokens are delivered
    //     await garden1.connect(signer2).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor4 = await garden1.getContributor(signer2.address);
    //     await expect(contributor4[4].toString()).to.equal(contributor3[4]);

    //     // Nos we finish the second strategy, it should not have given BABL rewards before

    //     await finishStrategyQ1(garden1, strategyContract2, 42);
    //     const [address4, active4, dataSet4, finalized4, executedAt4, exitedAt4] = await checkStrategyFinalized(
    //       strategyContract2,
    //     );

    //     // Check protocol
    //     const protocol3 = await rewardsDistributor.checkProtocol(exitedAt4);
    //     await checkProtocolTimestamp(protocol3, ethers.utils.parseEther('0'), exitedAt4, 1, 3, protocol3[4]); // TODO CHECK EXACT AMOUNT

    //     expect(protocol3[4]).to.not.equal(0); // TODO CHECK EXACT AMOUNT

    //     const protocolQuarter3 = await rewardsDistributor.checkQuarter(protocol3[2]);
    //     const [quarterPrincipal3, quarterNumber3, quarterPower3, quarterSupply3] = protocolQuarter3;
    //     await checkQuarterWithParams(
    //       quarterPrincipal3,
    //       quarterNumber3,
    //       quarterPower3,
    //       quarterSupply3,
    //       protocol3[0],
    //       1,
    //       protocol3[4],
    //       await rewardsDistributor.tokenSupplyPerQuarter(1),
    //     );

    //     // Signer 1 claim its tokens and check that they are received properly
    //     await garden1.connect(signer1).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor5 = await garden1.getContributor(signer1.address);
    //     // Try again to claim the same tokens but no more tokens are delivered
    //     await garden1.connect(signer1).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor6 = await garden1.getContributor(signer1.address);
    //     await expect(contributor6[4].toString()).to.equal(contributor5[4]);

    //     // Signer 2 claim his tokens and check that they are received properly
    //     await garden1.connect(signer2).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor7 = await garden1.getContributor(signer2.address);
    //     // Try again to claim the same tokens but no more tokens are delivered
    //     await garden1.connect(signer2).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor8 = await garden1.getContributor(signer2.address);
    //     await expect(contributor8[4].toString()).to.equal(contributor7[4]);
    //   });
    //   it('should only provide new additional BABL and profits between claims (claiming results of 2 strategies both with profit)', async function () {
    //     // Create strategy 1

    //     const strategyContract = await createStrategy(
    //       0,
    //       'vote',
    //       [signer1, signer2, signer3],
    //       kyberTradeIntegration.address,
    //       garden1,
    //     );

    //     // Create strategy 2

    //     const strategyContract2 = await createStrategy(
    //       0,
    //       'vote',
    //       [signer1, signer2, signer3],
    //       kyberTradeIntegration.address,
    //       garden1,
    //     );

    //     // Execute strategy 1
    //     await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42); // Strategy 1

    //     const [address, active, dataSet, finalized, executedAt, exitedAt, updatedAt] = await checkStrategyExecuted(
    //       strategyContract,
    //     );

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

    //     // Execute strategy 2, 2 days later

    //     await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('2'), 42); // Strategy 2

    //     const [
    //       address2,
    //       active2,
    //       dataSet2,
    //       finalized2,
    //       executedAt2,
    //       exitedAt2,
    //       updatedAt2,
    //     ] = await checkStrategyExecuted(strategyContract2);

    //     // Check protocol
    //     const protocol = await rewardsDistributor.checkProtocol(updatedAt2);
    //     await checkProtocolTimestamp(protocol, ethers.utils.parseEther('3'), executedAt2, 1, 1, protocol[4]);

    //     const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
    //     const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
    //     await checkQuarterWithParams(
    //       quarterPrincipal,
    //       quarterNumber,
    //       quarterPower,
    //       quarterSupply,
    //       ethers.utils.parseEther('3'),
    //       1,
    //       protocol[4],
    //       await rewardsDistributor.tokenSupplyPerQuarter(1),
    //     );

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

    //     await injectFakeProfits(strategyContract, ethers.utils.parseEther('200'));
    //     await finishStrategyQ1(garden1, strategyContract, 42);

    //     const [
    //       address3,
    //       active3,
    //       dataSet3,
    //       finalized3,
    //       executedAt3,
    //       exitedAt3,
    //       updatedAt3,
    //     ] = await checkStrategyFinalized(strategyContract);

    //     // Check protocol
    //     const protocol2 = await rewardsDistributor.checkProtocol(updatedAt3);
    //     await checkProtocolTimestamp(protocol2, ethers.utils.parseEther('2'), exitedAt3, 1, 2, protocol2[4]); // TODO CHECK EXACT AMOUNT

    //     expect(protocol2[4]).to.not.equal(0); // TODO Check exact numbers

    //     const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
    //     const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
    //     await checkQuarterWithParams(
    //       quarterPrincipal2,
    //       quarterNumber2,
    //       quarterPower2,
    //       quarterSupply2,
    //       protocol2[0],
    //       1,
    //       protocol2[4],
    //       await rewardsDistributor.tokenSupplyPerQuarter(1),
    //     );

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

    //     const bablRewards1 = await strategyContract.strategyRewards();
    //     const bablRewards2 = await strategyContract2.strategyRewards();

    //     // Transfer 500_000e18 tokens from owner to rewardsDistributor for BABL Mining Program
    //     const value = ethers.utils.parseEther('500000');
    //     await bablToken.connect(owner).transfer(rewardsDistributor.address, value);

    //     // Check Balances
    //     const ownerBalance = await bablToken.balanceOf(owner.address);
    //     const rewardsDistributorBalance = await bablToken.balanceOf(rewardsDistributor.address);

    //     expect(await bablToken.totalSupply()).to.equal(BigInt(ownerBalance) + BigInt(rewardsDistributorBalance));

    //     // Signer 1 claim its tokens and check that they are received properly
    //     await garden1.connect(signer1).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor = await garden1.getContributor(signer1.address);

    //     // Try again to claim the same tokens but no more tokens are delivered
    //     await garden1.connect(signer1).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor2 = await garden1.getContributor(signer1.address);
    //     await expect(contributor2[4].toString()).to.equal(contributor[4]);

    //     // Signer 2 claim his tokens and check that they are received properly
    //     await garden1.connect(signer2).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor3 = await garden1.getContributor(signer2.address);
    //     // Try again to claim the same tokens but no more tokens are delivered
    //     await garden1.connect(signer2).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor4 = await garden1.getContributor(signer2.address);
    //     await expect(contributor4[4].toString()).to.equal(contributor3[4]);

    //     // Now we finish the second strategy, it should not have given BABL rewards before

    //     await injectFakeProfits(strategyContract2, ethers.utils.parseEther('200'));
    //     await finishStrategyQ1(garden1, strategyContract2, 42);
    //     const [address4, active4, dataSet4, finalized4, executedAt4, exitedAt4] = await checkStrategyFinalized(
    //       strategyContract2,
    //     );

    //     // Check protocol
    //     const protocol3 = await rewardsDistributor.checkProtocol(exitedAt4);
    //     await checkProtocolTimestamp(protocol3, ethers.utils.parseEther('0'), exitedAt4, 1, 3, protocol3[4]); // TODO CHECK EXACT AMOUNT

    //     expect(protocol3[4]).to.not.equal(0); // TODO CHECK EXACT AMOUNT

    //     const protocolQuarter3 = await rewardsDistributor.checkQuarter(protocol3[2]);
    //     const [quarterPrincipal3, quarterNumber3, quarterPower3, quarterSupply3] = protocolQuarter3;
    //     await checkQuarterWithParams(
    //       quarterPrincipal3,
    //       quarterNumber3,
    //       quarterPower3,
    //       quarterSupply3,
    //       protocol3[0],
    //       1,
    //       protocol3[4],
    //       await rewardsDistributor.tokenSupplyPerQuarter(1),
    //     );

    //     // Signer 1 claim its tokens and check that they are received properly
    //     await garden1.connect(signer1).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor5 = await garden1.getContributor(signer1.address);

    //     // Try again to claim the same tokens but no more tokens are delivered
    //     await garden1.connect(signer1).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor6 = await garden1.getContributor(signer1.address);
    //     await expect(contributor6[4].toString()).to.equal(contributor5[4]);

    //     // Signer 2 claim his tokens and check that they are received properly
    //     await garden1.connect(signer2).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor7 = await garden1.getContributor(signer2.address);
    //     // Try again to claim the same tokens but no more tokens are delivered
    //     await garden1.connect(signer2).claimReturns([strategyContract.address, strategyContract2.address]);
    //     const contributor8 = await garden1.getContributor(signer2.address);
    //     await expect(contributor8[4].toString()).to.equal(contributor7[4]);
    //   });

    //   it('should check potential claim values of Profit and BABL Rewards', async function () {
    //     // Create strategy 1

    //     const strategyContract = await createStrategy(
    //       0,
    //       'vote',
    //       [signer1, signer2, signer3],
    //       kyberTradeIntegration.address,
    //       garden1,
    //     );

    //     // Create strategy 2

    //     const strategyContract2 = await createStrategy(
    //       0,
    //       'vote',
    //       [signer1, signer2, signer3],
    //       kyberTradeIntegration.address,
    //       garden1,
    //     );

    //     // Execute strategy 1
    //     await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42); // Strategy 1

    //     const [address, active, dataSet, finalized, executedAt, exitedAt, updatedAt] = await checkStrategyExecuted(
    //       strategyContract,
    //     );

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

    //     // Execute strategy 2, 2 days later

    //     await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('2'), 42); // Strategy 2

    //     const [
    //       address2,
    //       active2,
    //       dataSet2,
    //       finalized2,
    //       executedAt2,
    //       exitedAt2,
    //       updatedAt2,
    //     ] = await checkStrategyExecuted(strategyContract2);

    //     // Check protocol
    //     const protocol = await rewardsDistributor.checkProtocol(updatedAt2);
    //     await checkProtocolTimestamp(protocol, ethers.utils.parseEther('3'), executedAt2, 1, 1, protocol[4]);

    //     const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
    //     const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
    //     await checkQuarterWithParams(
    //       quarterPrincipal,
    //       quarterNumber,
    //       quarterPower,
    //       quarterSupply,
    //       ethers.utils.parseEther('3'),
    //       1,
    //       protocol[4],
    //       await rewardsDistributor.tokenSupplyPerQuarter(1),
    //     );

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

    //     await injectFakeProfits(strategyContract, ethers.utils.parseEther('200'));
    //     await finishStrategyQ1(garden1, strategyContract, 42);

    //     const [
    //       address3,
    //       active3,
    //       dataSet3,
    //       finalized3,
    //       executedAt3,
    //       exitedAt3,
    //       updatedAt3,
    //     ] = await checkStrategyFinalized(strategyContract);

    //     // Check protocol
    //     const protocol2 = await rewardsDistributor.checkProtocol(updatedAt3);
    //     await checkProtocolTimestamp(protocol2, ethers.utils.parseEther('2'), exitedAt3, 1, 2, protocol2[4]); // TODO CHECK EXACT AMOUNT

    //     expect(protocol2[4]).to.not.equal(0); // TODO Check exact numbers

    //     const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
    //     const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
    //     await checkQuarterWithParams(
    //       quarterPrincipal2,
    //       quarterNumber2,
    //       quarterPower2,
    //       quarterSupply2,
    //       protocol2[0],
    //       1,
    //       protocol2[4],
    //       await rewardsDistributor.tokenSupplyPerQuarter(1),
    //     );

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

    //     await finishStrategyQ1(garden1, strategyContract2, 42);
    //     const [address4, active4, dataSet4, finalized4, executedAt4, exitedAt4] = await checkStrategyFinalized(
    //       strategyContract2,
    //     );

    //     // Check protocol
    //     const protocol3 = await rewardsDistributor.checkProtocol(exitedAt4);
    //     await checkProtocolTimestamp(protocol3, ethers.utils.parseEther('0'), exitedAt4, 1, 3, protocol3[4]); // TODO CHECK EXACT AMOUNT

    //     expect(protocol3[4]).to.not.equal(0); // TODO CHECK EXACT AMOUNT

    //     const protocolQuarter3 = await rewardsDistributor.checkQuarter(protocol3[2]);
    //     const [quarterPrincipal3, quarterNumber3, quarterPower3, quarterSupply3] = protocolQuarter3;
    //     await checkQuarterWithParams(
    //       quarterPrincipal3,
    //       quarterNumber3,
    //       quarterPower3,
    //       quarterSupply3,
    //       protocol3[0],
    //       1,
    //       protocol3[4],
    //       await rewardsDistributor.tokenSupplyPerQuarter(1),
    //     );

    //     const bablRewards1 = await strategyContract.strategyRewards();
    //     const bablRewards2 = await strategyContract2.strategyRewards();

    //     // Transfer 500_000e18 tokens from owner to rewardsDistributor for BABL Mining Program
    //     const value = ethers.utils.parseEther('500000');
    //     await bablToken.connect(owner).transfer(rewardsDistributor.address, value);

    //     // Check Balances
    //     const ownerBalance = await bablToken.balanceOf(owner.address);
    //     const rewardsDistributorBalance = await bablToken.balanceOf(rewardsDistributor.address);

    //     expect(await bablToken.totalSupply()).to.equal(BigInt(ownerBalance) + BigInt(rewardsDistributorBalance));

    //     const rewards = await garden1
    //       .connect(signer1)
    //       .getProfitsAndBabl([strategyContract.address, strategyContract2.address]);

    //     expect(rewards[0].toString()).to.lt(ethers.utils.parseEther('1'));
    //     expect(rewards[1].toString()).to.gt(ethers.utils.parseEther('29000'));
    //   });

    //   it('should claim and update balances of Signer 1 either Garden tokens or BABL rewards as contributor of 5 strategies (4 with positive profits) of 2 different Gardens with different timings along 3 Years', async function () {
    //     // Create strategy 1

    //     const strategyContract1 = await createStrategy(
    //       0,
    //       'vote',
    //       [signer1, signer2, signer3],
    //       kyberTradeIntegration.address,
    //       garden1,
    //     );

    //     // Create strategy 2

    //     const strategyContract2 = await createStrategy(
    //       0,
    //       'vote',
    //       [signer1, signer2, signer3],
    //       kyberTradeIntegration.address,
    //       garden1,
    //     );

    //     // Create strategy 3

    //     const strategyContract3 = await createStrategy(
    //       0,
    //       'vote',
    //       [signer1, signer2, signer3],
    //       kyberTradeIntegration.address,
    //       garden2,
    //     );

    //     // Create strategy 4

    //     const strategyContract4 = await createStrategy(
    //       0,
    //       'vote',
    //       [signer1, signer2, signer3],
    //       kyberTradeIntegration.address,
    //       garden2,
    //     );
    //     // Create strategy 5

    //     const strategyContract5 = await createStrategy(
    //       0,
    //       'vote',
    //       [signer1, signer2, signer3],
    //       kyberTradeIntegration.address,
    //       garden2,
    //     );
    //     // Execute strategy 1
    //     await executeStrategy(garden1, strategyContract1, ethers.utils.parseEther('1'), 42); // Strategy 1

    //     const [address, active, dataSet, finalized, executedAt, exitedAt, updatedAt] = await checkStrategyExecuted(
    //       strategyContract1,
    //     );

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
    //     // Execute strategy 2
    //     await executeStrategy(garden1, strategyContract2, ethers.utils.parseEther('1'), 42); // Strategy 2
    //     // Execute strategy 3
    //     await executeStrategy(garden2, strategyContract3, ethers.utils.parseEther('1'), 42); // Strategy 3

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
    //     // Execute strategy 4
    //     await executeStrategy(garden2, strategyContract4, ethers.utils.parseEther('1'), 42); // Strategy 4
    //     // Execute strategy 5
    //     await executeStrategy(garden2, strategyContract5, ethers.utils.parseEther('1'), 42); // Strategy 5

    //     const [
    //       address2,
    //       active2,
    //       dataSet2,
    //       finalized2,
    //       executedAt2,
    //       exitedAt2,
    //       updatedAt2,
    //     ] = await checkStrategyExecuted(strategyContract5);

    //     // Check protocol
    //     const protocol = await rewardsDistributor.checkProtocol(updatedAt2);
    //     await checkProtocolTimestamp(protocol, ethers.utils.parseEther('5'), executedAt2, 1, 4, protocol[4]);
    //     // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

    //     const protocolQuarter = await rewardsDistributor.checkQuarter(protocol[2]);
    //     const [quarterPrincipal, quarterNumber, quarterPower, quarterSupply] = protocolQuarter;
    //     await checkQuarterWithParams(
    //       quarterPrincipal,
    //       quarterNumber,
    //       quarterPower,
    //       quarterSupply,
    //       ethers.utils.parseEther('5'),
    //       1,
    //       protocol[4],
    //       await rewardsDistributor.tokenSupplyPerQuarter(1),
    //     );
    //     // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

    //     ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

    //     await injectFakeProfits(strategyContract1, ethers.utils.parseEther('200'));
    //     await finishStrategyQ1NoIncreaseTime(garden1, strategyContract1, 42);

    //     await finishStrategy2Q(garden1, strategyContract2, 42);

    //     await injectFakeProfits(strategyContract3, ethers.utils.parseEther('200'));
    //     await finishStrategy2Y(garden2, strategyContract3, 42); // Increase time 2 years

    //     await injectFakeProfits(strategyContract4, ethers.utils.parseEther('222'));
    //     await finishStrategy2Q(garden2, strategyContract4, 42);

    //     await injectFakeProfits(strategyContract5, ethers.utils.parseEther('222'));
    //     await finishStrategy3Q(garden2, strategyContract5, 42);
    //     const [
    //       address3,
    //       active3,
    //       dataSet3,
    //       finalized3,
    //       executedAt3,
    //       exitedAt3,
    //       updatedAt3,
    //     ] = await checkStrategyFinalized(strategyContract5);

    //     // Check protocol
    //     const protocol2 = await rewardsDistributor.checkProtocol(updatedAt3);
    //     await checkProtocolTimestamp(protocol2, ethers.utils.parseEther('0'), exitedAt3, 13, 9, protocol2[4]); // TODO CHECK EXACT AMOUNT
    //     // PARAMS checkProtocolWithParams(_protocol, _principal, _timestamp, _quarter, _timeListPointer, _power)

    //     const protocolQuarter2 = await rewardsDistributor.checkQuarter(protocol2[2]);
    //     const [quarterPrincipal2, quarterNumber2, quarterPower2, quarterSupply2] = protocolQuarter2;
    //     await checkQuarterWithParams(
    //       quarterPrincipal2,
    //       quarterNumber2,
    //       quarterPower2,
    //       quarterSupply2,
    //       protocol2[0],
    //       13,
    //       quarterPower2,
    //       await rewardsDistributor.tokenSupplyPerQuarter(13),
    //     );
    //     // PARAMS checkQuarterWithParams(_quarter0, _quarter1, _quarter2, _quarter3, _principal, _quarter, _power, _supply)

    //     const bablRewards1 = await strategyContract1.strategyRewards();
    //     const bablRewards2 = await strategyContract2.strategyRewards();
    //     const bablRewards3 = await strategyContract3.strategyRewards();
    //     const bablRewards4 = await strategyContract4.strategyRewards();
    //     const bablRewards5 = await strategyContract5.strategyRewards();

    //     // Transfer 500_000e18 tokens from owner to rewardsDistributor for BABL Mining Program
    //     const value = ethers.utils.parseEther('500000');
    //     await bablToken.connect(owner).transfer(rewardsDistributor.address, value);

    //     // Check Balances
    //     const ownerBalance = await bablToken.balanceOf(owner.address);
    //     const rewardsDistributorBalance = await bablToken.balanceOf(rewardsDistributor.address);

    //     expect(await bablToken.totalSupply()).to.equal(BigInt(ownerBalance) + BigInt(rewardsDistributorBalance));

    //     // We claim our tokens and check that they are received properly
    //     await garden1.connect(signer1).claimReturns([strategyContract1.address, strategyContract2.address]);
    //     const signer1Balance1 = await bablToken.balanceOf(signer1.address);
    //     const signer1Profit1 = await garden1.balanceOf(signer1.address);

    //     await garden2
    //       .connect(signer1)
    //       .claimReturns([strategyContract3.address, strategyContract4.address, strategyContract5.address]);
    //     const signer1Balance2 = await bablToken.balanceOf(signer1.address);
    //     const signer1Profit2 = await garden2.balanceOf(signer1.address);

    //     expect(signer1Balance2.toString()).to.gt(ethers.utils.parseEther('258000'));
    //     expect(signer1Profit1.toString()).to.gt(ethers.utils.parseEther('3'));
    //     expect(signer1Profit2.toString()).to.gt(ethers.utils.parseEther('8'));
    //   });
    // });
  });
});
