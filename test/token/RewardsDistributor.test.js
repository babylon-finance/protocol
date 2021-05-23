const { expect } = require('chai');

const { ONE_DAY_IN_SECONDS, ONE_ETH } = require('../../lib/constants');
const { increaseTime } = require('../utils/test-helpers');

const {
  createStrategy,
  executeStrategy,
  injectFakeProfits,
  finalizeStrategyImmediate,
  finalizeStrategyAfterQuarter,
  finalizeStrategyAfter2Quarters,
  finalizeStrategyAfter30Days,
  finalizeStrategyAfter2Years,
  finalizeStrategyAfter3Quarters,
} = require('../fixtures/StrategyHelper.js');

const { setupTests } = require('../fixtures/GardenFixture');

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
        'buy',
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
    } = await setupTests()());

    await bablToken.connect(owner).enableTokensTransfers();
  });

  describe('Deployment', function () {
    it('should successfully deploy BABL Mining Rewards Distributor contract', async function () {
      const deployedc = await rewardsDistributor.deployed(bablToken.address, babController.address);
      expect(!!deployedc).to.equal(true);
    });
  });

  describe('Strategy BABL Mining Rewards Calculation', async function () {
    it('should protect from overflow returning 0 supply in totalSupplyPerQuarter >= 513 (128 years)', async function () {
      await expect((await rewardsDistributor.tokenSupplyPerQuarter(455)).toString()).to.be.equal('2');
      await expect((await rewardsDistributor.tokenSupplyPerQuarter(462)).toString()).to.be.equal('1');
      await expect((await rewardsDistributor.tokenSupplyPerQuarter(463)).toString()).to.be.equal('0');
      await expect((await rewardsDistributor.tokenSupplyPerQuarter(512)).toString()).to.be.equal('0');
      await expect((await rewardsDistributor.tokenSupplyPerQuarter(513)).toString()).to.be.equal('0');
      await expect((await rewardsDistributor.tokenSupplyPerQuarter(700)).toString()).to.be.equal('0');
    });
    it('should get 0 BABL rewards if the Mining Program has not started yet', async function () {
      const [long] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long, ONE_ETH);
      await finalizeStrategyAfter30Days(long);
      expect((await long.strategyRewards()).toString()).to.be.equal('0');
    });
    it('should get 0 BABL rewards if the Mining Program starts after the creation of an strategy', async function () {
      const [long] = await createStrategies([{ garden: garden1 }]);
      // Mining program has to be enabled before the strategy is created
      await babController.connect(owner).enableBABLMiningProgram();
      await executeStrategy(long, ONE_ETH);

      await finalizeStrategyAfter30Days(long);

      expect((await long.strategyRewards()).toString()).to.be.equal('0');
    });
    it('should get 0 BABL rewards if the Mining Program starts in the middle of an strategy execution', async function () {
      const [long] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long, ONE_ETH);
      // Mining program has to be enabled before the strategy is created
      await babController.connect(owner).enableBABLMiningProgram();
      await finalizeStrategyAfter30Days(long);

      expect((await long.strategyRewards()).toString()).to.be.equal('0');
    });
    it('should fail trying to calculate rewards of a strategy that has not ended yet', async function () {
      const [long] = await createStrategies([{ garden: garden1 }]);

      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

      await executeStrategy(long, ONE_ETH);

      await expect(rewardsDistributor.getStrategyRewards(long.address)).to.be.revertedWith('revert BAB#049');
    });

    it('should calculate correct BABL in case of 1 strategy with negative profit and total duration of 1 quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

      const [long1] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);

      const { updatedAt } = await getStrategyState(long1);
      // Check principal normalized to DAI
      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: '3911436663717185355925',
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
      expect((await long1.strategyRewards()).toString()).to.be.closeTo(
        '53252867971266677419386',
        ethers.utils.parseEther('0.10'),
      );
    });

    it('should calculate correct BABL in case of 1 strategy with positive profit and with total duration of 1 quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

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

      expect((await long1.strategyRewards()).toString()).to.be.closeTo(
        '56245433363508517711850',
        ethers.utils.parseEther('0.10'),
      );
    });

    it('should calculate correct BABL in case of 2 strategies with total duration of 1 quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await finalizeStrategyAfter30Days(long1);

      const { exitedAt } = await getStrategyState(long1);

      // Check principal normalized to DAI
      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: '3911436663717185355925',
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

      expect((await long1.strategyRewards()).toString()).to.be.closeTo(
        '27132419508506259553580',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long2.strategyRewards()).toString()).to.be.closeTo(
        '35047470808640457275688',
        ethers.utils.parseEther('0.10'),
      );
    });

    it('should calculate correct BABL in case of 3 strategies with total duration of 1 quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

      const [long1, long2, long3] = await createStrategies([
        { garden: garden1 },
        { garden: garden1 },
        { garden: garden1 },
      ]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH);
      await executeStrategy(long3, ONE_ETH);

      const { updatedAt } = await getStrategyState(long3);
      // Check principal normalized to DAI
      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: '11734309991151556067775',
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
      expect((await long1.strategyRewards()).toString()).to.be.closeTo(
        '18414360810740186824305',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long2.strategyRewards()).toString()).to.be.closeTo(
        '17781600117468574435385',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long3.strategyRewards()).toString()).to.be.closeTo(
        '17184592362734916590598',
        ethers.utils.parseEther('0.10'),
      );
    });

    it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with total duration of less than 1 quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

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

      // Check principal normalized to DAI
      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: '19557183318585926779625',
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

      expect((await long1.strategyRewards()).toString()).to.be.closeTo(
        '11419076202165184207617',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long2.strategyRewards()).toString()).to.be.closeTo(
        '11044001745689719476197',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long3.strategyRewards()).toString()).to.be.closeTo(
        '10682716204848241431450',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long4.strategyRewards()).toString()).to.be.closeTo(
        '10334270615144077320828',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long5.strategyRewards()).toString()).to.be.closeTo(
        '9998260599911546111505',
        ethers.utils.parseEther('0.10'),
      );
    });

    it('should calculate correct BABL in case of 1 strategy with total duration of 2 quarters', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

      const [long1] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);

      await finalizeStrategyAfter2Quarters(long1);
      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 3,
        timeListPointer: 1,
      });
      expect((await long1.strategyRewards()).toString()).to.be.closeTo(
        '101429390403440602823930',
        ethers.utils.parseEther('0.10'),
      );
    });

    it('should calculate correct BABL in the future (10 years) in case of 1 strategy with total duration of 2 quarters', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

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
      expect((await long1.strategyRewards()).toString()).to.be.closeTo(
        '1343503648201374544096',
        ethers.utils.parseEther('0.10'),
      );
    });

    it('should calculate correct BABL rewards in case of 1 strategy with total duration of 3 quarters', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

      const [long1] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);

      await finalizeStrategyAfter3Quarters(long1);
      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 4,
        timeListPointer: 1,
      });
      expect((await long1.strategyRewards()).toString()).to.be.closeTo(
        '143814823688624358512181',
        ethers.utils.parseEther('0.10'),
      );
    });

    it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with different timings along 3 quarters', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

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

      // Check principal normalized to DAI
      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: '19557183318585926779625',
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

      expect((await long1.strategyRewards()).toString()).to.be.closeTo(
        '14746686400974691978871',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long2.strategyRewards()).toString()).to.be.closeTo(
        '36027272426754649843657',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long3.strategyRewards()).toString()).to.be.closeTo(
        '47764584261311153592536',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long4.strategyRewards()).toString()).to.be.closeTo(
        '77709264981258266348085',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long5.strategyRewards()).toString()).to.be.closeTo(
        '144676471940142761206850',
        ethers.utils.parseEther('0.10'),
      );
    });

    it('should calculate correct BABL (in 10 Years from now) in case of 5 strategies of 2 different Gardens with different timings along 3 quarters', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const [long1, long2, long3, long4, long5] = await createStrategies([
        { garden: garden1 },
        { garden: garden1 },
        { garden: garden2 },
        { garden: garden2 },
        { garden: garden2 },
      ]);

      increaseTime(ONE_DAY_IN_SECONDS * 3650);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH);
      await executeStrategy(long3, ONE_ETH);
      await executeStrategy(long4, ONE_ETH);
      await executeStrategy(long5, ONE_ETH);

      const { updatedAt } = await getStrategyState(long5);

      // Check principal normalized to DAI
      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: '19557183318585926779625',
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

      expect((await long1.strategyRewards()).toString()).to.be.closeTo(
        '219505782600391978866',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long2.strategyRewards()).toString()).to.be.closeTo(
        '432866381321524321541',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long3.strategyRewards()).toString()).to.be.closeTo(
        '550877848075216077400',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long4.strategyRewards()).toString()).to.be.closeTo(
        '855311059338348715428',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long5.strategyRewards()).toString()).to.be.closeTo(
        '1548564705482122746208',
        ethers.utils.parseEther('0.10'),
      );
    });

    it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with different timings along 3 Years', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

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

      expect((await long1.strategyRewards()).toString()).to.be.closeTo(
        '14746684630519643055653',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long2.strategyRewards()).toString()).to.be.closeTo(
        '36027274829677121559080',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long3.strategyRewards()).toString()).to.be.closeTo(
        '103496845269185705914380',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long4.strategyRewards()).toString()).to.be.closeTo(
        '116777460754824659278346',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long5.strategyRewards()).toString()).to.be.closeTo(
        '146632702332807071553557',
        ethers.utils.parseEther('0.10'),
      );
    });

    it('should calculate correct BABL in case of 5 (4 with positive profits) strategies of 2 different Gardens with different timings along 3 Years', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

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

      expect((await long1.strategyRewards()).toString()).to.be.closeTo(
        '15494254972521277311382',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long2.strategyRewards()).toString()).to.be.closeTo(
        '36027097055554831892944',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long3.strategyRewards()).toString()).to.be.closeTo(
        '108743822308976618676953',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long4.strategyRewards()).toString()).to.be.closeTo(
        '122697700153741837968774',
        ethers.utils.parseEther('0.10'),
      );
      expect((await long5.strategyRewards()).toString()).to.be.closeTo(
        '154873256672811739176857',
        ethers.utils.parseEther('0.10'),
      );
    });
  });

  describe('Claiming Reserve Asset Rewards and BABL Rewards', function () {
    it('should claim and update balances of Signer1 either Garden tokens or BABL rewards as contributor of 2 strategies (1 with positive profits and other without them) within a quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await injectFakeProfits(long1, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long1);

      await finalizeStrategyAfterQuarter(long2);

      // We claim our tokens and check that they are received properly
      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);

      expect(await bablToken.balanceOf(signer1.address)).to.gt(ONE_ETH.mul(29000));
      expect(await garden1.balanceOf(signer1.address)).to.gt(ONE_ETH.mul(2));
    });

    it('should not allow a race condition of two consecutive claims for the same rewards & profit of the same strategies', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await injectFakeProfits(long1, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long1);

      await finalizeStrategyAfterQuarter(long2);

      // Check pending rewards for users
      const [, signer1BABL] = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);
      const [, signer2BABL] = await rewardsDistributor.getRewards(garden1.address, signer2.address, [
        long1.address,
        long2.address,
      ]);

      // Balances before claiming
      const signer1GardenBalance = await garden1.balanceOf(signer1.address);
      const signer2GardenBalance = await garden1.balanceOf(signer2.address);

      expect((await bablToken.balanceOf(signer1.address)).toString()).to.be.equal('0');
      expect((await bablToken.balanceOf(signer2.address)).toString()).to.be.equal('0');

      // Signer1 claims its tokens and check that they are received properly
      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);
      const contributor = await garden1.getContributor(signer1.address);

      // Try again to claims the same tokens but no more tokens are delivered
      await expect(garden1.connect(signer1).claimReturns([long1.address, long2.address])).to.be.revertedWith(
        'revert BAB#082',
      );
      const contributor2 = await garden1.getContributor(signer1.address);

      await expect(contributor2[4].toString()).to.equal(contributor[4]);

      // Signer2 claims his tokens and check that they are received properly
      await garden1.connect(signer2).claimReturns([long1.address, long2.address]);
      const contributor3 = await garden1.getContributor(signer2.address);

      // Try again to claims the same tokens but as there are no more tokens or rewards, it reverts
      await expect(garden1.connect(signer2).claimReturns([long1.address, long2.address])).to.be.revertedWith(
        'revert BAB#082',
      );
      const contributor4 = await garden1.getContributor(signer2.address);

      await expect(contributor4[4].toString()).to.equal(contributor3[4]);

      // Check pending rewards for users (shouldn´t be any as they are already claimed)

      const [signer1Profits2, signer1BABL2] = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);
      const [signer2Profits2, signer2BABL2] = await rewardsDistributor.getRewards(garden1.address, signer2.address, [
        long1.address,
        long2.address,
      ]);

      expect(signer1Profits2.toString()).to.be.equal('0');
      expect(signer1BABL2.toString()).to.be.equal('0');
      expect(signer2Profits2.toString()).to.be.equal('0');
      expect(signer2BABL2.toString()).to.be.equal('0');

      expect((await bablToken.balanceOf(signer1.address)).toString()).to.be.equal(signer1BABL);
      expect((await bablToken.balanceOf(signer2.address)).toString()).to.be.equal(signer2BABL);
      expect((await garden1.balanceOf(signer1.address)).toString()).to.be.equal(signer1GardenBalance);
      expect((await garden1.balanceOf(signer2.address)).toString()).to.be.equal(signer2GardenBalance);
    });

    it('should only provide new additional BABL and profits between claims (claiming results of 2 strategies only 1 with profit)', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await injectFakeProfits(long1, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long1);

      expect((await bablToken.balanceOf(signer1.address)).toString()).to.be.equal('0');

      const [signer1Profit, signer1BABL] = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);

      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);
      expect((await bablToken.balanceOf(signer1.address)).toString()).to.be.equal(signer1BABL);
      expect(signer1Profit.toString()).to.be.closeTo('4647439471332470', ethers.utils.parseEther('0.00005'));
      const [signer1Profit2, signer1BABL2] = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);
      expect(signer1Profit2.toString()).to.be.equal('0');
      expect(signer1BABL2.toString()).to.be.equal('0');
      increaseTime(ONE_DAY_IN_SECONDS * 10);

      await finalizeStrategyAfterQuarter(long2);
      const [signer1Profit3, signer1BABL3] = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);

      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);
      expect(signer1Profit3.toString()).to.be.equal('0'); // Negative profit means no profit at all
      expect(signer1BABL3.toString()).to.be.closeTo('37701789043050854045289', ethers.utils.parseEther('0.1'));
    });

    it('should only provide new additional BABL and profits between claims (claiming results of 2 strategies both with profit)', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await injectFakeProfits(long1, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long1);

      const [signer1Profit, signer1BABL] = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);
      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);

      await injectFakeProfits(long2, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long2);
      const [signer1Profit2, signer1BABL2] = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);
      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);
      expect(signer1Profit.toString()).to.be.not.equal(signer1Profit2);
      expect(signer1Profit).to.be.closeTo('50085069448375857', ethers.utils.parseEther('0.10'));
      expect(signer1Profit2).to.be.closeTo('49258870032308262', ethers.utils.parseEther('0.10'));
      expect((await bablToken.balanceOf(signer1.address)).toString()).to.be.equal(signer1BABL.add(signer1BABL2));
    });

    it('should check potential claim values of Profit and BABL Rewards', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await injectFakeProfits(long1, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long1);

      await injectFakeProfits(long2, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long2);
      const [signer1Profit, signer1BABL] = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);

      // TODO: Add calculations of profits and BABL
      expect(signer1Profit).to.be.closeTo('9245294724499069', ethers.utils.parseEther('0.005'));
      expect(signer1BABL).to.be.closeTo('64734257580754107362234', ethers.utils.parseEther('0.1'));
    });

    it('should claim and update balances of Signer1 either Garden tokens or BABL rewards as contributor of 5 strategies (4 with positive profits) of 2 different Gardens with different timings along 3 Years', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

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
      const [signer1Profit, signer1BABL] = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);
      const [signer2Profit, signer2BABL] = await rewardsDistributor.getRewards(garden1.address, signer2.address, [
        long1.address,
        long2.address,
      ]);

      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);
      await garden1.connect(signer2).claimReturns([long1.address, long2.address]);

      expect((await bablToken.balanceOf(signer1.address)).toString()).to.be.equal(signer1BABL);
      expect((await bablToken.balanceOf(signer2.address)).toString()).to.be.equal(signer2BABL);
      expect(signer1Profit.toString()).to.be.closeTo('4679132243339230', ethers.utils.parseEther('0.0005'));
      expect(signer2Profit.toString()).to.be.closeTo('283583772323589', ethers.utils.parseEther('0.0005'));
      const [signer1Profit2, signer1BABL2] = await rewardsDistributor.getRewards(garden2.address, signer1.address, [
        long3.address,
        long4.address,
        long5.address,
      ]);
      const [signer2Profit2, signer2BABL2] = await rewardsDistributor.getRewards(garden2.address, signer2.address, [
        long3.address,
        long4.address,
        long5.address,
      ]);

      await garden2.connect(signer1).claimReturns([long3.address, long4.address, long5.address]);
      await garden2.connect(signer2).claimReturns([long3.address, long4.address, long5.address]);

      expect((await bablToken.balanceOf(signer1.address)).toString()).to.be.equal(signer1BABL2.add(signer1BABL));
      expect((await bablToken.balanceOf(signer2.address)).toString()).to.be.equal(signer2BABL2.add(signer2BABL));

      expect(signer1Profit2.toString()).to.be.closeTo('14880369451856172', ethers.utils.parseEther('0.0005'));
      expect(signer2Profit2.toString()).to.be.closeTo('1045112496393399', ethers.utils.parseEther('0.0005'));
    });
    it('A user cannot claim strategies from 2 different gardens at the same time avoiding malicious bypassing of the claimedAt control (e.g. using claimedAtfrom different gardens over the same strategies)', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

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

      await finalizeStrategyAfterQuarter(long2);

      await injectFakeProfits(long3, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long3);

      await injectFakeProfits(long4, ONE_ETH.mul(222));
      await finalizeStrategyAfterQuarter(long4);

      await injectFakeProfits(long5, ONE_ETH.mul(222));
      await finalizeStrategyAfterQuarter(long5);

      // We try to hack the system bypassing claimedAt mistmaching different gardens with different strategies
      await expect(
        garden1
          .connect(signer1)
          .claimReturns([long1.address, long2.address, long3.address, long4.address, long5.address]),
      ).to.be.revertedWith('revert BAB#073');
    });
    it('A user cannot get rewards from strategies of 2 different gardens at the same time avoiding malicious bypassing of the claimedAt control (e.g. using claimedAtfrom different gardens over the same strategies)', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

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

      await finalizeStrategyAfterQuarter(long2);

      await injectFakeProfits(long3, ONE_ETH.mul(200));
      await finalizeStrategyAfterQuarter(long3);

      await injectFakeProfits(long4, ONE_ETH.mul(222));
      await finalizeStrategyAfterQuarter(long4);

      await injectFakeProfits(long5, ONE_ETH.mul(222));
      await finalizeStrategyAfterQuarter(long5);

      // We try to hack the system bypassing claimedAt mistmaching different gardens with different strategies

      await expect(
        rewardsDistributor.getRewards(garden2.address, signer1.address, [
          long1.address,
          long2.address,
          long3.address,
          long4.address,
          long5.address,
        ]),
      ).to.be.revertedWith('revert BAB#073');
    });
  });
});
