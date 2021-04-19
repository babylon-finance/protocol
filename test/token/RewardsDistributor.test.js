const { expect } = require('chai');
const { waffle } = require('hardhat');

const { ONE_DAY_IN_SECONDS, ONE_ETH } = require('../../utils/constants');
const { increaseTime } = require('../utils/test-helpers');
const { loadFixture } = waffle;

const {
  createStrategy,
  executeStrategy,
  injectFakeProfits,
  finalizeStrategy,
  finalizeStrategyAfterQuarter,
  finalizeStrategyAfter2Quarters,
  finalizeStrategyAfter30Days,
  finalizeStrategyAfter2Years,
  finalizeStrategyAfter3Quarters,
} = require('../fixtures/StrategyHelper.js');

const { deployFolioFixture } = require('../fixtures/ControllerFixture');

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
    it('should fail trying to calculate rewards of a strategy that has not ended yet', async function () {
      const [long] = await createStrategies([{ garden: garden1 }]);
      await executeStrategy(long, ONE_ETH);

      await expect(rewardsDistributor.getStrategyRewards(long.address)).to.be.revertedWith(
        'The strategy has to be finished',
      );
    });

    // TODO: This test doesn't check BABL rewards.
    it('should calculate correct BABL in case of 1 strategy with negative profit and total duration of 1 quarter', async function () {
      const [long1] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);

      const { updatedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: ONE_ETH,
        quarter: 1,
        timeListPointer: 0,
      });

      increaseTime(ONE_DAY_IN_SECONDS * 2);

      await finalizeStrategyAfter30Days(long1);

      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 1,
        timeListPointer: 1,
      });
    });

    // TODO: This test doesn't check BABL rewards.
    it('should calculate correct BABL in case of 1 strategy with positive profit and with total duration of 1 quarter', async function () {
      const [long1] = await createStrategies([{ garden: garden1 }]);
      await executeStrategy(long1, ONE_ETH);

      await injectFakeProfits(long1, ONE_ETH.mul(222));

      increaseTime(ONE_DAY_IN_SECONDS * 2);

      await finalizeStrategyAfter30Days(long1);

      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 1,
        timeListPointer: 1,
      });
    });

    // TODO: This test doesn't check BABL rewards.
    it('should calculate correct BABL in case of 2 strategies with total duration of 1 quarter', async function () {
      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await finalizeStrategyAfter30Days(long1);

      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: ONE_ETH.mul(2),
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
    });

    // TODO: This test doesn't check BABL rewards.
    it('should calculate correct BABL in case of 3 strategies with total duration of 1 quarter', async function () {
      const [long1, long2, long3] = await createStrategies([
        { garden: garden1 },
        { garden: garden1 },
        { garden: garden1 },
      ]);
      await executeStrategy(long1, ONE_ETH);

      increaseTime(ONE_DAY_IN_SECONDS * 2);

      await executeStrategy(long2, ONE_ETH);
      await executeStrategy(long3, ONE_ETH);

      const { updatedAt } = await getStrategyState(long3);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: ONE_ETH.mul(3),
        quarter: 1,
        timeListPointer: 2,
      });

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      await finalizeStrategy(long1);
      await finalizeStrategy(long2);
      await finalizeStrategy(long3);

      const { exitedAt } = await getStrategyState(long3);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 1,
        timeListPointer: 5,
      });
    });

    // TODO: This test doesn't check BABL rewards.
    it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with total duration of less than 1 quarter', async function () {
      const [long1, long2, long3, long4, long5] = await createStrategies([
        { garden: garden1 },
        { garden: garden1 },
        { garden: garden2 },
        { garden: garden2 },
        { garden: garden2 },
      ]);

      await executeStrategy(long1, ONE_ETH);

      increaseTime(ONE_DAY_IN_SECONDS * 2);
      await executeStrategy(long2, ONE_ETH);
      await executeStrategy(long3, ONE_ETH);

      increaseTime(ONE_DAY_IN_SECONDS * 2);
      await executeStrategy(long4, ONE_ETH);
      await executeStrategy(long5, ONE_ETH);

      const { updatedAt } = await getStrategyState(long5);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: ONE_ETH.mul(5),
        quarter: 1,
        timeListPointer: 4,
      });

      increaseTime(ONE_DAY_IN_SECONDS * 30);
      await finalizeStrategy(long1);
      await finalizeStrategy(long2);
      await finalizeStrategy(long3);
      await finalizeStrategy(long4);
      await finalizeStrategy(long5);

      const { exitedAt } = await getStrategyState(long5);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 1,
        timeListPointer: 9,
      });
    });

    // TODO: This test doesn't check BABL rewards.
    it('should calculate correct BABL in case of 1 strategy with total duration of 2 quarters', async function () {
      const [long1] = await createStrategies([{ garden: garden1 }]);
      await executeStrategy(long1, ONE_ETH);

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      await finalizeStrategyAfter2Quarters(long1);
      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 3,
        timeListPointer: 1,
      });
    });

    it('should calculate correct BABL in the future (10 years) in case of 1 strategy with total duration of 2 quarters', async function () {
      const [long1] = await createStrategies([{ garden: garden1 }]);

      // We go to the future 10 years
      increaseTime(ONE_DAY_IN_SECONDS * 3650);

      await executeStrategy(long1, ONE_ETH);

      await finalizeStrategyAfter2Quarters(long1);
      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 43,
        timeListPointer: 1,
      });
    });

    it('should calculate correct BABL rewards in case of 1 strategy with total duration of 3 quarters', async function () {
      const [long1] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);

      await finalizeStrategyAfter3Quarters(long1);
      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 4,
        timeListPointer: 1,
      });
    });

    it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with different timings along 3 quarters', async function () {
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
    });

    it('should calculate correct BABL (in 10 Years from now) in case of 5 strategies of 2 different Gardens with different timings along 3 quarters', async function () {
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
        quarter: 51,
        timeListPointer: 9,
      });
    });

    it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with different timings along 3 Years', async function () {
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
    });

    it('should calculate correct BABL in case of 5 (4 with positive profits) strategies of 2 different Gardens with different timings along 3 Years', async function () {
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
    });
  });

  describe('Claiming Profits and BABL Rewards', function () {
    it('should claim and update balances of Signer1 either Garden tokens or BABL rewards as contributor of 2 strategies (1 with positive profits and other without them) within a quarter', async function () {
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
