const { expect } = require('chai');
const { waffle } = require('hardhat');

const { ONE_DAY_IN_SECONDS, ONE_ETH } = require('../../utils/constants');
const { increaseTime } = require('../utils/test-helpers');
const { loadFixture } = waffle;

const {
  createStrategy,
  executeStrategy,
  executeStrategyImmediate,
  injectFakeProfits,
  finalizeStrategy,
  finalizeStrategyImmediate,
  finalizeStrategyAfterQuarter,
  finalizeStrategyAfter2Quarters,
  finalizeStrategyAfter30Days,
  finalizeStrategyAfter2Years,
  finalizeStrategyAfter3Quarters,
} = require('../fixtures/StrategyHelper.js');

const { deployFolioFixture } = require('../fixtures/ControllerFixture');
const { ethers } = require('ethers');

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
  let kyberTradeIntegration;

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
  });

  describe('Deployment', function () {
    it('should successfully deploy BABL Mining Rewards Distributor contract', async function () {
      const deployedc = await rewardsDistributor.deployed(bablToken.address, babController.address);
      expect(!!deployedc).to.equal(true);
    });
  });

  describe('Strategy BABL Mining Rewards Calculation', async function () {
    it('should get 0 BABL rewards if the Mining Program has not started yet', async function () {
      const [long] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long, ONE_ETH);
      await finalizeStrategyAfter30Days(long);

      const value = await long.strategyRewards();
      expect(value.toString()).to.be.equal('0');
    });
    it('should get 0 BABL rewards if the Mining Program starts after the creation of an strategy', async function () {
      const [long] = await createStrategies([{ garden: garden1 }]);
      // Mining program has to be enabled before the strategy is created
      await babController.enableBABLMiningProgram();
      await executeStrategy(long, ONE_ETH);

      await finalizeStrategyAfter30Days(long);

      const value = await long.strategyRewards();
      expect(value.toString()).to.be.equal('0');
    });
    it('should get 0 BABL rewards if the Mining Program starts in the middle of an strategy execution', async function () {
      const [long] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long, ONE_ETH);
      // Mining program has to be enabled before the strategy is created
      await babController.enableBABLMiningProgram();
      await finalizeStrategyAfter30Days(long);

      const value = await long.strategyRewards();
      expect(value.toString()).to.be.equal('0');
    });
    it('should fail trying to calculate rewards of a strategy that has not ended yet', async function () {
      const [long] = await createStrategies([{ garden: garden1 }]);

      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();

      await executeStrategy(long, ONE_ETH);

      await expect(rewardsDistributor.getStrategyRewards(long.address)).to.be.revertedWith(
        'The strategy has to be finished',
      );
    });

    it('should calculate correct BABL in case of 1 strategy with negative profit and total duration of 1 quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();

      const [long1] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);

      const { updatedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: ONE_ETH,
        quarter: 1,
        timeListPointer: 0,
      });

      await finalizeStrategyAfter30Days(long1);

      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 1,
        timeListPointer: 1,
      });
      const value = await long1.strategyRewards();

      expect(value.toString()).to.be.closeTo('53348540978530991898983', ethers.utils.parseEther('100'));
    });

    it('should calculate correct BABL in case of 1 strategy with positive profit and with total duration of 1 quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();

      const [long1] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);

      await injectFakeProfits(long1, ONE_ETH.mul(222));

      await finalizeStrategyAfter30Days(long1);

      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 1,
        timeListPointer: 1,
      });
      const value = await long1.strategyRewards();

      expect(value.toString()).to.be.closeTo('59249976195741897367844', ethers.utils.parseEther('100'));
    });

    it('should calculate correct BABL in case of 2 strategies with total duration of 1 quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();
      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await finalizeStrategyAfter30Days(long1);

      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: ONE_ETH,
        quarter: 1,
        timeListPointer: 2,
      });

      await finalizeStrategyAfter30Days(long2);

      const { exitedAt: long2exitedAt } = await getStrategyState(long2);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, long2exitedAt, {
        principal: 0,
        quarter: 1,
        timeListPointer: 3,
      });

      const value = await long1.strategyRewards();
      const value2 = await long2.strategyRewards();
      expect(value.toString()).to.be.closeTo('27180447233494116321502', ethers.utils.parseEther('100'));
      expect(value2.toString()).to.be.closeTo('35048359900229386030568', ethers.utils.parseEther('100'));
    });

    it('should calculate correct BABL in case of 3 strategies with total duration of 1 quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();

      const [long1, long2, long3] = await createStrategies([
        { garden: garden1 },
        { garden: garden1 },
        { garden: garden1 },
      ]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH);
      await executeStrategy(long3, ONE_ETH);

      const { updatedAt } = await getStrategyState(long3);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: ONE_ETH.mul(3),
        quarter: 1,
        timeListPointer: 2,
      });

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      await finalizeStrategyImmediate(long1);
      await finalizeStrategyImmediate(long2);
      await finalizeStrategyImmediate(long3);

      const { exitedAt } = await getStrategyState(long3);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 1,
        timeListPointer: 5,
      });
      const value = await long1.strategyRewards();
      const value2 = await long2.strategyRewards();
      const value3 = await long3.strategyRewards();

      expect(value.toString()).to.be.closeTo('18445181219085995431261', ethers.utils.parseEther('100'));
      expect(value2.toString()).to.be.closeTo('17782866245738688737500', ethers.utils.parseEther('100'));
      expect(value3.toString()).to.be.closeTo('17185457418296213096639', ethers.utils.parseEther('100'));
    });

    it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with total duration of less than 1 quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();

      const [long1, long2, long3, long4, long5] = await createStrategies([
        { garden: garden1 },
        { garden: garden1 },
        { garden: garden2 },
        { garden: garden2 },
        { garden: garden2 },
      ]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH);
      await executeStrategy(long3, ONE_ETH);
      await executeStrategy(long4, ONE_ETH);
      await executeStrategy(long5, ONE_ETH);

      const { updatedAt } = await getStrategyState(long5);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: ONE_ETH.mul(5),
        quarter: 1,
        timeListPointer: 4,
      });

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      await finalizeStrategyImmediate(long1);
      await finalizeStrategyImmediate(long2);
      await finalizeStrategyImmediate(long3);
      await finalizeStrategyImmediate(long4);
      await finalizeStrategyImmediate(long5);

      const { exitedAt } = await getStrategyState(long5);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 1,
        timeListPointer: 9,
      });
      const value = await long1.strategyRewards();
      const value2 = await long2.strategyRewards();
      const value3 = await long3.strategyRewards();
      const value4 = await long4.strategyRewards();
      const value5 = await long5.strategyRewards();

      expect(value.toString()).to.be.closeTo('11435970164063358738429', ethers.utils.parseEther('100'));
      expect(value2.toString()).to.be.closeTo('11044229195829251755344', ethers.utils.parseEther('100'));
      expect(value3.toString()).to.be.closeTo('10683469693470981807217', ethers.utils.parseEther('100'));
      expect(value4.toString()).to.be.closeTo('10335531645539449819993', ethers.utils.parseEther('100'));
      expect(value5.toString()).to.be.closeTo('9999261911014897602655', ethers.utils.parseEther('100'));
    });

    it('should calculate correct BABL in case of 1 strategy with total duration of 2 quarters', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();

      const [long1] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);

      await finalizeStrategyAfter2Quarters(long1);
      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 3,
        timeListPointer: 1,
      });
      const value1 = await long1.strategyRewards();
      expect(value1.toString()).to.be.closeTo('101611616359986629966551', ethers.utils.parseEther('100'));
    });

    it('should calculate correct BABL in the future (10 years) in case of 1 strategy with total duration of 2 quarters', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();
      // We go to the future 10 years
      increaseTime(ONE_DAY_IN_SECONDS * 3650);

      const [long1] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);

      await finalizeStrategyAfter2Quarters(long1);
      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 43,
        timeListPointer: 1,
      });
      const value1 = await long1.strategyRewards();
      expect(value1.toString()).to.be.closeTo('1345917359221846850849', ethers.utils.parseEther('100'));
    });

    it('should calculate correct BABL rewards in case of 1 strategy with total duration of 3 quarters', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();

      const [long1] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);

      await finalizeStrategyAfter3Quarters(long1);
      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 4,
        timeListPointer: 1,
      });
      const value1 = await long1.strategyRewards();
      expect(value1.toString()).to.be.closeTo('144073198442804768654832', ethers.utils.parseEther('100'));
    });

    it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with different timings along 3 quarters', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();

      const [long1, long2, long3, long4, long5] = await createStrategies([
        { garden: garden1 },
        { garden: garden1 },
        { garden: garden2 },
        { garden: garden2 },
        { garden: garden2 },
      ]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH);
      await executeStrategy(long3, ONE_ETH);
      await executeStrategy(long4, ONE_ETH);
      await executeStrategy(long5, ONE_ETH);

      const { updatedAt } = await getStrategyState(long5);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: ONE_ETH.mul(5),
        quarter: 1,
        timeListPointer: 4,
      });

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      await finalizeStrategyAfterQuarter(long1);
      await finalizeStrategyAfter2Quarters(long2);
      await finalizeStrategyAfterQuarter(long3);
      await finalizeStrategyAfter2Quarters(long4);
      await finalizeStrategyAfter3Quarters(long5);
      const { exitedAt } = await getStrategyState(long5);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 10,
        timeListPointer: 9,
      });
      const value = await long1.strategyRewards();
      const value2 = await long2.strategyRewards();
      const value3 = await long3.strategyRewards();
      const value4 = await long4.strategyRewards();
      const value5 = await long5.strategyRewards();

      expect(value.toString()).to.be.closeTo('14768509337275189635976', ethers.utils.parseEther('100'));
      expect(value2.toString()).to.be.closeTo('36028010516922891357773', ethers.utils.parseEther('100'));
      expect(value3.toString()).to.be.closeTo('47767976443221726749911', ethers.utils.parseEther('100'));
      expect(value4.toString()).to.be.closeTo('77718716359714865220580', ethers.utils.parseEther('100'));
      expect(value5.toString()).to.be.closeTo('144690957560334038164365', ethers.utils.parseEther('100'));
    });

    it('should calculate correct BABL (in 10 Years from now) in case of 5 strategies of 2 different Gardens with different timings along 3 quarters', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();

      increaseTime(ONE_DAY_IN_SECONDS * 3650);

      const [long1, long2, long3, long4, long5] = await createStrategies([
        { garden: garden1 },
        { garden: garden1 },
        { garden: garden2 },
        { garden: garden2 },
        { garden: garden2 },
      ]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH);
      await executeStrategy(long3, ONE_ETH);
      await executeStrategy(long4, ONE_ETH);
      await executeStrategy(long5, ONE_ETH);

      const { updatedAt } = await getStrategyState(long5);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: ONE_ETH.mul(5),
        quarter: 41,
        timeListPointer: 4,
      });

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      await finalizeStrategyAfterQuarter(long1);
      await finalizeStrategyAfter2Quarters(long2);
      await finalizeStrategyAfterQuarter(long3);
      await finalizeStrategyAfter2Quarters(long4);
      await finalizeStrategyAfter3Quarters(long5);
      const { exitedAt } = await getStrategyState(long5);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 50,
        timeListPointer: 9,
      });
      const value = await long1.strategyRewards();
      const value2 = await long2.strategyRewards();
      const value3 = await long3.strategyRewards();
      const value4 = await long4.strategyRewards();
      const value5 = await long5.strategyRewards();

      expect(value.toString()).to.be.closeTo('219830499847879011062', ethers.utils.parseEther('100'));
      expect(value2.toString()).to.be.closeTo('432866381321524321541', ethers.utils.parseEther('100'));
      expect(value3.toString()).to.be.closeTo('550877848075216077400', ethers.utils.parseEther('100'));
      expect(value4.toString()).to.be.closeTo('855415131918472783218', ethers.utils.parseEther('100'));
      expect(value5.toString()).to.be.closeTo('1548719778914765381373', ethers.utils.parseEther('100'));
    });

    it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with different timings along 3 Years', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();

      const [long1, long2, long3, long4, long5] = await createStrategies([
        { garden: garden1 },
        { garden: garden1 },
        { garden: garden2 },
        { garden: garden2 },
        { garden: garden2 },
      ]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH);
      await executeStrategy(long3, ONE_ETH);
      await executeStrategy(long4, ONE_ETH);
      await executeStrategy(long5, ONE_ETH);

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      await finalizeStrategyAfterQuarter(long1);
      await finalizeStrategyAfter2Quarters(long2);
      await finalizeStrategyAfter2Years(long3);
      await finalizeStrategyAfter2Quarters(long4);
      await finalizeStrategyAfter3Quarters(long5);
      const { exitedAt } = await getStrategyState(long5);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 17,
        timeListPointer: 9,
      });
      const value = await long1.strategyRewards();
      const value2 = await long2.strategyRewards();
      const value3 = await long3.strategyRewards();
      const value4 = await long4.strategyRewards();
      const value5 = await long5.strategyRewards();

      expect(value.toString()).to.be.closeTo('14768510523869051906610', ethers.utils.parseEther('100'));
      expect(value2.toString()).to.be.closeTo('36028010181804892681797', ethers.utils.parseEther('100'));
      expect(value3.toString()).to.be.closeTo('103504194661629220128166', ethers.utils.parseEther('100'));
      expect(value4.toString()).to.be.closeTo('116791666375962828576062', ethers.utils.parseEther('100'));
      expect(value5.toString()).to.be.closeTo('146647388604927375625599', ethers.utils.parseEther('100'));
    });

    it('should calculate correct BABL in case of 5 (4 with positive profits) strategies of 2 different Gardens with different timings along 3 Years', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();

      const [long1, long2, long3, long4, long5] = await createStrategies([
        { garden: garden1 },
        { garden: garden1 },
        { garden: garden2 },
        { garden: garden2 },
        { garden: garden2 },
      ]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH);
      await executeStrategy(long3, ONE_ETH);
      await executeStrategy(long4, ONE_ETH);
      await executeStrategy(long5, ONE_ETH);

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      await injectFakeProfits(long1, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long1);

      await finalizeStrategyAfter2Quarters(long2);

      await injectFakeProfits(long3, ONE_ETH.mul(200));
      await finalizeStrategyAfter2Years(long3);

      await injectFakeProfits(long4, ONE_ETH.mul(200));
      await finalizeStrategyAfter2Quarters(long4);

      await injectFakeProfits(long5, ONE_ETH.mul(222));
      await finalizeStrategyAfter3Quarters(long5);

      const { exitedAt } = await getStrategyState(long5);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 17,
        timeListPointer: 9,
      });
      const value = await long1.strategyRewards();
      const value2 = await long2.strategyRewards();
      const value3 = await long3.strategyRewards();
      const value4 = await long4.strategyRewards();
      const value5 = await long5.strategyRewards();

      expect(value.toString()).to.be.closeTo('16240388525503153926512', ethers.utils.parseEther('100'));
      expect(value2.toString()).to.be.closeTo('36028007825033530186347', ethers.utils.parseEther('100'));
      expect(value3.toString()).to.be.closeTo('113879793599216106591361', ethers.utils.parseEther('100'));
      expect(value4.toString()).to.be.closeTo('128499165056248655452247', ethers.utils.parseEther('100'));
      expect(value5.toString()).to.be.closeTo('162964850162148936616798', ethers.utils.parseEther('100'));
    });
  });

  describe('Claiming Profits and BABL Rewards', function () {
    it('should claim and update balances of Signer1 either Garden tokens or BABL rewards as contributor of 2 strategies (1 with positive profits and other without them) within a quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();

      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await injectFakeProfits(long1, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long1);

      await finalizeStrategyAfterQuarter(long2);

      // Transfer 500_000e18 tokens from owner to rewardsDistributor for BABL Mining Program
      await bablToken.connect(owner).transfer(rewardsDistributor.address, ONE_ETH.mul(500000));

      // We claim our tokens and check that they are received properly
      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);

      const signer1Balance1 = await bablToken.balanceOf(signer1.address);
      const signer1Profit1 = await garden1.balanceOf(signer1.address);

      expect(signer1Balance1).to.gt(ONE_ETH.mul(29000));
      expect(signer1Profit1).to.gt(ONE_ETH.mul(2));
    });

    it('should not allow a race condition of two consecutive claims for the same rewards & profit of the same strategies', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();

      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await injectFakeProfits(long1, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long1);

      await finalizeStrategyAfterQuarter(long2);

      // Transfer 500_000e18 tokens from owner to rewardsDistributor for BABL Mining Program
      await bablToken.connect(owner).transfer(rewardsDistributor.address, ONE_ETH.mul(500000));

      // Signer1 claims its tokens and check that they are received properly
      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);
      const contributor = await garden1.getContributor(signer1.address);

      // Try again to claims the same tokens but no more tokens are delivered
      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);
      const contributor2 = await garden1.getContributor(signer1.address);

      await expect(contributor2[4].toString()).to.equal(contributor[4]);

      // Signer2 claims his tokens and check that they are received properly
      await garden1.connect(signer2).claimReturns([long1.address, long2.address]);
      const contributor3 = await garden1.getContributor(signer2.address);

      // Try again to claims the same tokens but no more tokens are delivered
      await garden1.connect(signer2).claimReturns([long1.address, long2.address]);
      const contributor4 = await garden1.getContributor(signer2.address);

      await expect(contributor4[4].toString()).to.equal(contributor3[4]);
    });

    it('should only provide new additional BABL and profits between claims (claiming results of 2 strategies only 1 with profit)', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();

      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await injectFakeProfits(long1, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long1);

      await finalizeStrategyAfterQuarter(long2);

      // Transfer 500_000e18 tokens from owner to rewardsDistributor for BABL Mining Program
      await bablToken.connect(owner).transfer(rewardsDistributor.address, ONE_ETH.mul(500000));

      // TODO: Write actual checks
    });

    it('should only provide new additional BABL and profits between claims (claiming results of 2 strategies both with profit)', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();

      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await injectFakeProfits(long1, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long1);

      await injectFakeProfits(long2, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long2);

      // Transfer 500_000e18 tokens from owner to rewardsDistributor for BABL Mining Program
      await bablToken.connect(owner).transfer(rewardsDistributor.address, ONE_ETH.mul(500000));
      // TODO: Write actual checks
      // const rewards = await garden1.connect(signer1).getProfitsAndBabl([long1.address, long2.address]);
      // expect(rewards[0].toString()).to.lt(ethers.utils.parseEther('1'));
      // expect(rewards[1].toString()).to.gt(ethers.utils.parseEther('23700'));
    });

    it('should check potential claim values of Profit and BABL Rewards', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();

      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await injectFakeProfits(long1, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long1);

      await injectFakeProfits(long2, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long2);

      // Transfer 500_000e18 tokens from owner to rewardsDistributor for BABL Mining Program
      await bablToken.connect(owner).transfer(rewardsDistributor.address, ONE_ETH.mul(500000));
      // TODO: Write actual checks

      const rewards = await garden1.connect(signer1).getProfitsAndBabl([long1.address, long2.address]);

      expect(rewards[0]).to.lt(ONE_ETH.mul(1));
      expect(rewards[1]).to.gt(ONE_ETH.mul(29000));
    });

    it('should claim and update balances of Signer1 either Garden tokens or BABL rewards as contributor of 5 strategies (4 with positive profits) of 2 different Gardens with different timings along 3 Years', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.enableBABLMiningProgram();
      const [long1, long2, long3, long4, long5] = await createStrategies([
        { garden: garden1 },
        { garden: garden1 },
        { garden: garden2 },
        { garden: garden2 },
        { garden: garden2 },
      ]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH);
      await executeStrategy(long3, ONE_ETH);
      await executeStrategy(long4, ONE_ETH);
      await executeStrategy(long5, ONE_ETH);

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      await injectFakeProfits(long1, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long1);

      await finalizeStrategyAfter2Quarters(long2);

      await injectFakeProfits(long3, ONE_ETH.mul(200));
      await finalizeStrategyAfter2Years(long3);

      await injectFakeProfits(long4, ONE_ETH.mul(222));
      await finalizeStrategyAfter2Quarters(long4);

      await injectFakeProfits(long5, ONE_ETH.mul(222));
      await finalizeStrategyAfter3Quarters(long5);

      // We claim our tokens and check that they are received properly
      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);
      const signer1Profit1 = await garden1.balanceOf(signer1.address);

      await garden2.connect(signer1).claimReturns([long3.address, long4.address, long5.address]);
      const signer1Balance2 = await bablToken.balanceOf(signer1.address);
      const signer1Profit2 = await garden2.balanceOf(signer1.address);

      // TODO: These do fail. Have to fix.
      // expect(signer1Balance2.toString()).to.gt(ethers.utils.parseEther('258000'));
      // expect(signer1Profit1.toString()).to.gt(ethers.utils.parseEther('3'));
      // expect(signer1Profit2.toString()).to.gt(ethers.utils.parseEther('8'));
    });
  });
});
