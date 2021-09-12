const { expect } = require('chai');
const {
  ONE_DAY_IN_SECONDS,
  ONE_ETH,
  GARDEN_PARAMS_STABLE,
  USDC_GARDEN_PARAMS,
  STRATEGY_EXECUTE_MAP,
} = require('lib/constants');
const { increaseTime, increaseBlock } = require('utils/test-helpers');

const { parse } = require('lib/helpers');
const { impersonateAddress } = require('lib/rpc');
const addresses = require('lib/addresses');

const {
  createStrategy,
  executeStrategy,
  injectFakeProfits,
  substractFakeProfits,
  finalizeStrategyImmediate,
  finalizeStrategyAfterQuarter,
  finalizeStrategyAfter2Quarters,
  finalizeStrategyAfter30Days,
  finalizeStrategyAfter2Years,
  finalizeStrategyAfter3Quarters,
  USDC_STRATEGY_PARAMS,
  DAI_STRATEGY_PARAMS,
} = require('fixtures/StrategyHelper.js');
const { createGarden, transferFunds, depositFunds } = require('fixtures/GardenHelper');

const { setupTests } = require('fixtures/GardenFixture');
const { ADDRESS_ZERO } = require('../../../lib/constants');

async function getAndValidateProtocolTimestamp(rewardsDistributor, timestamp, protocolPerTimestamp) {
  const [principal, time, quarterBelonging, timeListPointer, power] = await rewardsDistributor.checkProtocol(timestamp);
  const obj = { principal, time, quarterBelonging, timeListPointer, power };

  expect(obj.principal).to.be.closeTo(
    ethers.BigNumber.from(protocolPerTimestamp.principal),
    ethers.BigNumber.from(protocolPerTimestamp.principal).div(100),
  ); // 1% slippage
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

  expect(obj.quarterPrincipal).to.be.closeTo(
    ethers.BigNumber.from(quarterObj.quarterPrincipal),
    ethers.BigNumber.from(quarterObj.quarterPrincipal).div(100),
  ); // 1% slippage
  expect(obj.quarterNumber).to.eq(quarterObj.quarterNumber);
  // TODO: Check for power
  // expect(obj.quarterPower).to.eq(quarterObj.quarterPower);
  expect(obj.supplyPerQuarter).to.eq(quarterObj.supplyPerQuarter);

  return obj;
}

async function getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, timestamp, protocolObj) {
  /**
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
   */
}

async function getStrategyState(strategy) {
  const [address, active, dataSet, finalized, executedAt, exitedAt, updatedAt] = await strategy.getStrategyState();

  return { address, active, dataSet, finalized, executedAt, exitedAt, updatedAt };
}

describe('RewardsDistributor', function () {
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let babController;
  let bablToken;
  let rewardsDistributor;
  let ishtarGate;
  let garden1;
  let garden2;
  let daiGarden;
  let usdcGarden;
  let usdc;
  let dai;
  let weth;
  let priceOracle;
  let uniswapV3TradeIntegration;
  let masterSwapper;

  async function createStrategies(strategies) {
    const retVal = [];
    for (let i = 0; i < strategies.length; i++) {
      const strategy = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        masterSwapper.address,
        strategies[i].garden,
      );
      retVal.push(strategy);
    }
    return retVal;
  }

  async function getStrategyRewards(strategy, now, quarterStart, quarterEnd, powerRatio) {
    let rewards = 0;
    let timePercent = 0;
    // We calculate the profit of the strategy
    const allocated = await strategy.capitalAllocated();
    let returned = await strategy.capitalReturned();

    if (returned > allocated * 2) {
      // We simulate the protocol cap x2
      returned = allocated.mul(2).mul(ONE_ETH).div(ONE_ETH);
    }
    const profit = ethers.BigNumber.from(returned).mul(ONE_ETH).div(ethers.BigNumber.from(allocated));
    const [, , , , , exitedAt] = await strategy.getStrategyState();
    const bablSupplyQ1 = await rewardsDistributor.tokenSupplyPerQuarter(quarterStart);

    if (quarterStart !== quarterEnd) {
      // More than 1 quarter
      const bablTokenQi = [];
      const supplyPerQuarter = [];
      for (let i = 0; i <= quarterEnd - quarterStart; i++) {
        supplyPerQuarter[i] = await rewardsDistributor.tokenSupplyPerQuarter(quarterStart + i);
        if (i === 0) {
          // First
          timePercent = ONE_ETH;
          bablTokenQi[i] = powerRatio[i]
            .mul(profit)
            .mul(supplyPerQuarter[i])
            .mul(timePercent)
            .div(ONE_ETH)
            .mul(ONE_ETH)
            .div(ONE_ETH)
            .div(ONE_ETH)
            .div(ONE_ETH);
          rewards = bablTokenQi[i];
        } else if (i > 0 && i <= quarterEnd - quarterStart - 1) {
          // intermediate quarters
          timePercent = ONE_ETH;
          bablTokenQi[i] = powerRatio[i]
            .mul(profit)
            .mul(supplyPerQuarter[i])
            .mul(timePercent)
            .div(ONE_ETH)
            .mul(ONE_ETH)
            .div(ONE_ETH)
            .div(ONE_ETH)
            .div(ONE_ETH);
          rewards = rewards.add(bablTokenQi[i]);
        } else if (i === quarterEnd - quarterStart) {
          // last quarter
          timePercent = ethers.BigNumber.from(
            exitedAt.toNumber() - (now + 90 * ONE_DAY_IN_SECONDS * (quarterStart + i - 1)),
          )
            .mul(ONE_ETH)
            .div(ethers.BigNumber.from(90 * ONE_DAY_IN_SECONDS));
          bablTokenQi[i] = powerRatio[i]
            .mul(profit)
            .mul(supplyPerQuarter[i])
            .mul(timePercent)
            .div(ONE_ETH)
            .mul(ONE_ETH)
            .div(ONE_ETH)
            .div(ONE_ETH)
            .div(ONE_ETH);
          rewards = rewards.add(bablTokenQi[i]);
        }
      }
    } else if (quarterStart === quarterEnd) {
      // The same quarter
      const timePercent = ethers.BigNumber.from(exitedAt.toNumber() - now)
        .mul(ONE_ETH)
        .div(ethers.BigNumber.from(90 * ONE_DAY_IN_SECONDS));
      const bablTokensQ1 = powerRatio[0]
        .mul(profit)
        .mul(bablSupplyQ1)
        .mul(timePercent)
        .div(ONE_ETH)
        .mul(ONE_ETH)
        .div(ONE_ETH)
        .div(ONE_ETH)
        .div(ONE_ETH);
      rewards = bablTokensQ1;
    }

    return rewards;
  }

  beforeEach(async () => {
    ({
      owner,
      signer1,
      signer2,
      signer3,
      garden1,
      garden2,
      daiGarden,
      usdcGarden,
      usdc,
      babController,
      bablToken,
      rewardsDistributor,
      ishtarGate,
      uniswapV3TradeIntegration,
      priceOracle,
      masterSwapper,
    } = await setupTests()());

    await bablToken.connect(owner).enableTokensTransfers();
    usdc = await ethers.getContractAt('@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20', addresses.tokens.USDC);
    dai = await ethers.getContractAt('@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20', addresses.tokens.DAI);
    weth = await ethers.getContractAt('@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20', addresses.tokens.WETH);
  });

  describe('Deployment', function () {
    it('should successfully deploy BABL Mining Rewards Distributor contract', async function () {
      const deployedc = await rewardsDistributor.deployed(bablToken.address, babController.address);
      expect(!!deployedc).to.equal(true);
    });
  });
  describe('setBABLToken', function () {
    it('can set a new BABL Token address', async function () {
      const newToken = await impersonateAddress('0xf4dc48d260c93ad6a96c5ce563e70ca578987c74');
      await expect(rewardsDistributor.connect(owner).setBablToken(newToken.address)).not.to.be.reverted;
    });
    it('can NOT set zero address as a new BABL Token address', async function () {
      await expect(rewardsDistributor.connect(owner).setBablToken(ADDRESS_ZERO)).to.be.revertedWith('BAB#096');
    });
  });

  describe('Strategy BABL Mining Rewards Calculation', async function () {
    it('should protect from overflow returning 0 supply in totalSupplyPerQuarter >= 513 (128 years)', async function () {
      await expect((await rewardsDistributor.tokenSupplyPerQuarter(455)).toString()).to.be.equal('2');
      await expect((await rewardsDistributor.tokenSupplyPerQuarter(462)).toString()).to.be.equal('1');
      await expect((await rewardsDistributor.tokenSupplyPerQuarter(463)).toString()).to.be.equal('0');
      await expect((await rewardsDistributor.tokenSupplyPerQuarter(512)).toString()).to.be.equal('0');
      // At 513 quarter the formula had an overflow, now it is fixed and still provides 0 tokens (it really provides 0 tokens since epoch 463 ahead but we avoid the overflow at 513).
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

      await expect(rewardsDistributor.getStrategyRewards(long.address)).to.be.revertedWith('BAB#049');
    });

    it('should calculate correct BABL in case of 1 strategy with negative profit and total duration of 1 quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const block = await ethers.provider.getBlock();
      const now = block.timestamp;

      const [long1] = await createStrategies([{ garden: garden1 }]);
      await executeStrategy(long1, ONE_ETH);

      const { updatedAt } = await getStrategyState(long1);
      // Check principal normalized to DAI
      const pricePerToken = await priceOracle.connect(owner).getPrice(addresses.tokens.WETH, addresses.tokens.DAI);
      const principalInDAI = pricePerToken.mul(ONE_ETH).div(ONE_ETH);
      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: principalInDAI,
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

      const value = await getStrategyRewards(long1, now, 1, 1, [ethers.utils.parseEther('1')]);
      const rewards = await long1.strategyRewards();
      expect(rewards).to.be.closeTo(value, ethers.utils.parseEther('0.005'));
    });
    it('should calculate correct BABL in an active strategy that was unwind before finishing (2 quarters)', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const block = await ethers.provider.getBlock();
      const now = block.timestamp;
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );
      expect(await weth.balanceOf(garden1.address)).to.be.gt(ethers.utils.parseEther('2'));

      await executeStrategy(strategyContract, { amount: ONE_ETH.mul(2) });

      expect(await weth.balanceOf(garden1.address)).to.be.closeTo(ONE_ETH.mul(3), ONE_ETH.div(100));
      expect(await strategyContract.capitalAllocated()).to.equal(ethers.utils.parseEther('2'));
      await increaseTime(ONE_DAY_IN_SECONDS * 70);
      await strategyContract.connect(owner).unwindStrategy(ONE_ETH);

      expect(await strategyContract.capitalAllocated()).to.equal(ethers.utils.parseEther('1'));
      expect(await weth.balanceOf(garden1.address)).to.be.gt(ethers.utils.parseEther('1'));
      await increaseTime(ONE_DAY_IN_SECONDS * 70);
      await finalizeStrategyAfter30Days(strategyContract);
      const value = await getStrategyRewards(strategyContract, now, 1, 2, [
        ethers.utils.parseEther('1'),
        ethers.utils.parseEther('1'),
      ]);
      const rewards = await strategyContract.strategyRewards();
      expect(rewards).to.be.closeTo(value, ethers.utils.parseEther('0.005'));
    });
    it('should calculate correct BABL in case of 1 strategy with negative profit and total duration of 1 quarter but crossing edges (2 quarters)', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const block = await ethers.provider.getBlock();
      const now = block.timestamp;

      // We try to hack the calculation of rewards taking time from 2 different epochs with a strategy lasting less than 1 epoch in total
      await increaseTime(ONE_DAY_IN_SECONDS * 70);

      const [long1] = await createStrategies([{ garden: garden1 }]);
      await executeStrategy(long1, ONE_ETH);

      await finalizeStrategyAfter30Days(long1);

      // Check protocol checkpoints are updated accordingly
      const { exitedAt } = await getStrategyState(long1);
      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 2,
        timeListPointer: 1,
      });
      const value = await getStrategyRewards(long1, now, 1, 2, [
        ethers.utils.parseEther('1'),
        ethers.utils.parseEther('1'),
      ]);
      const rewards = await long1.strategyRewards();
      expect(rewards).to.be.closeTo(value, ethers.utils.parseEther('0.005'));
    });

    it('should calculate correct BABL in case of 1 strategy with positive profit and with total duration of 1 quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const block = await ethers.provider.getBlock();
      const now = block.timestamp;

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

      const value = await getStrategyRewards(long1, now, 1, 1, [ethers.utils.parseEther('1')]);
      const rewards = await long1.strategyRewards();
      expect(rewards).to.be.closeTo(value, ethers.utils.parseEther('0.005'));
    });
    it('should not count malicious injected profit in BABL rewards calculation in case of 1 strategy with positive profit and with total duration of 1 quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const block = await ethers.provider.getBlock();
      const now = block.timestamp;

      const [long1] = await createStrategies([{ garden: garden1 }]);
      await executeStrategy(long1, ONE_ETH);

      await injectFakeProfits(long1, ONE_ETH.mul(222));

      // Here we inject malicious reserveAsset
      const whaleAddress = '0x2f0b23f53734252bda2277357e97e1517d6b042a';
      const whaleSigner = await impersonateAddress(whaleAddress);
      await weth.connect(whaleSigner).transfer(signer1.address, ONE_ETH.mul(100), {
        gasPrice: 0,
      });
      await weth.connect(signer1).transfer(long1.address, ONE_ETH.mul(100));
      await finalizeStrategyAfter30Days(long1);

      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 1,
        timeListPointer: 1,
      });

      const value = await getStrategyRewards(long1, now, 1, 1, [ethers.utils.parseEther('1')]);
      const rewards = await long1.strategyRewards();
      expect(rewards).to.be.closeTo(value, ethers.utils.parseEther('0.005'));
    });

    it('should calculate correct BABL in case of 2 strategies with total duration of 1 quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const block = await ethers.provider.getBlock();
      const now = block.timestamp;
      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await finalizeStrategyAfter30Days(long1);

      const { exitedAt } = await getStrategyState(long1);

      // Check principal normalized to DAI
      const pricePerToken = await priceOracle.connect(owner).getPrice(addresses.tokens.WETH, addresses.tokens.DAI);
      const principalInDAI = pricePerToken.mul(ONE_ETH).div(ONE_ETH);
      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: principalInDAI,
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

      const valueLong1 = await getStrategyRewards(long1, now, 1, 1, [ethers.utils.parseEther('0.5094881121')]);
      const valueLong2 = await getStrategyRewards(long2, now, 1, 1, [ethers.utils.parseEther('0.658179225')]);

      const rewardsLong1 = await long1.strategyRewards();
      const rewardsLong2 = await long2.strategyRewards();

      expect(rewardsLong1).to.be.closeTo(valueLong1, valueLong1.div(100));
      expect(rewardsLong2).to.be.closeTo(valueLong2, valueLong2.div(100));
    });

    it('should calculate correct BABL in case of 3 strategies with total duration of 1 quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const block = await ethers.provider.getBlock();
      const now = block.timestamp;

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
      const pricePerToken = await priceOracle.connect(owner).getPrice(addresses.tokens.WETH, addresses.tokens.DAI);
      const principalInDAI = pricePerToken.mul(ONE_ETH.mul(3)).div(ONE_ETH);
      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: principalInDAI,
        quarter: 1,
        timeListPointer: 2,
      });

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      await finalizeStrategyImmediate(long1);
      await finalizeStrategyImmediate(long2);
      await finalizeStrategyImmediate(long3);
      const { exitedAt: exitedAtLong3 } = await getStrategyState(long3);
      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAtLong3, {
        principal: 0,
        quarter: 1,
        timeListPointer: 5,
      });

      const valueLong1 = await getStrategyRewards(long1, now, 1, 1, [ethers.utils.parseEther('0.3457485554')]);
      const valueLong2 = await getStrategyRewards(long2, now, 1, 1, [ethers.utils.parseEther('0.3339235916')]);
      const valueLong3 = await getStrategyRewards(long3, now, 1, 1, [ethers.utils.parseEther('0.322751593')]);

      const rewardsLong1 = await long1.strategyRewards();
      const rewardsLong2 = await long2.strategyRewards();
      const rewardsLong3 = await long3.strategyRewards();

      expect(rewardsLong1).to.be.closeTo(valueLong1, valueLong1.div(100));
      expect(rewardsLong2).to.be.closeTo(valueLong2, valueLong2.div(100));
      expect(rewardsLong3).to.be.closeTo(valueLong3, valueLong3.div(100));
    });

    it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with total duration of less than 1 quarter', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const block = await ethers.provider.getBlock();
      const now = block.timestamp;

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
      const pricePerToken = await priceOracle.connect(owner).getPrice(addresses.tokens.WETH, addresses.tokens.DAI);
      const principalInDAI = pricePerToken.mul(ONE_ETH.mul(5)).div(ONE_ETH);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, updatedAt, {
        principal: principalInDAI,
        quarter: 1,
        timeListPointer: 4,
      });

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      await finalizeStrategyImmediate(long1);
      const { exitedAt: exitedAtLong1 } = await getStrategyState(long1);
      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAtLong1, {
        principal: pricePerToken.mul(ONE_ETH.mul(4)).div(ONE_ETH),
        quarter: 1,
        timeListPointer: 5,
      });
      await finalizeStrategyImmediate(long2);
      const { exitedAt: exitedAtLong2 } = await getStrategyState(long2);
      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAtLong2, {
        principal: pricePerToken.mul(ONE_ETH.mul(3)).div(ONE_ETH),
        quarter: 1,
        timeListPointer: 6,
      });

      await finalizeStrategyImmediate(long3);
      const { exitedAt: exitedAtLong3 } = await getStrategyState(long3);
      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAtLong3, {
        principal: pricePerToken.mul(ONE_ETH.mul(2)).div(ONE_ETH),
        quarter: 1,
        timeListPointer: 7,
      });

      await finalizeStrategyImmediate(long4);
      const { exitedAt: exitedAtLong4 } = await getStrategyState(long4);
      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAtLong4, {
        principal: pricePerToken.mul(ONE_ETH.mul(1)).div(ONE_ETH),
        quarter: 1,
        timeListPointer: 8,
      });

      await finalizeStrategyImmediate(long5);
      const { exitedAt: exitedAtLong5 } = await getStrategyState(long5);
      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAtLong5, {
        principal: 0,
        quarter: 1,
        timeListPointer: 9,
      });

      const valueLong1 = await getStrategyRewards(long1, now, 1, 1, [ethers.utils.parseEther('0.214363301')]);
      const valueLong2 = await getStrategyRewards(long2, now, 1, 1, [ethers.utils.parseEther('0.2073570029')]);
      const valueLong3 = await getStrategyRewards(long3, now, 1, 1, [ethers.utils.parseEther('0.2006124084')]);
      const valueLong4 = await getStrategyRewards(long4, now, 1, 1, [ethers.utils.parseEther('0.1941064651')]);
      const valueLong5 = await getStrategyRewards(long5, now, 1, 1, [ethers.utils.parseEther('0.1878178833')]);

      const rewardsLong1 = await long1.strategyRewards();
      const rewardsLong2 = await long2.strategyRewards();
      const rewardsLong3 = await long3.strategyRewards();
      const rewardsLong4 = await long4.strategyRewards();
      const rewardsLong5 = await long5.strategyRewards();

      expect(rewardsLong1).to.be.closeTo(valueLong1, valueLong1.div(100));
      expect(rewardsLong2).to.be.closeTo(valueLong2, valueLong2.div(100));
      expect(rewardsLong3).to.be.closeTo(valueLong3, valueLong3.div(100));
      expect(rewardsLong4).to.be.closeTo(valueLong4, valueLong4.div(100));
      expect(rewardsLong5).to.be.closeTo(valueLong5, valueLong5.div(100));
    });

    it('should calculate correct BABL in case of 1 strategy with total duration of 2 quarters', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const block = await ethers.provider.getBlock();
      const now = block.timestamp;

      const [long1] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);

      await finalizeStrategyAfter2Quarters(long1);

      const valueLong1 = await getStrategyRewards(long1, now, 1, 3, [
        ethers.utils.parseEther('1'),
        ethers.utils.parseEther('1'),
        ethers.utils.parseEther('1'),
      ]);
      const rewardsLong1 = await long1.strategyRewards();
      expect(rewardsLong1).to.be.closeTo(valueLong1, ethers.utils.parseEther('0.005'));
    });

    it('should calculate correct BABL in the future (10 years) in case of 1 strategy with total duration of 2 quarters', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const block = await ethers.provider.getBlock();
      const now = block.timestamp;

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

      const valueLong1 = await getStrategyRewards(long1, now, 41, 43, [
        ethers.utils.parseEther('1'),
        ethers.utils.parseEther('1'),
        ethers.utils.parseEther('1'),
      ]);
      const rewardsLong1 = await long1.strategyRewards();
      expect(rewardsLong1).to.be.closeTo(valueLong1, ethers.utils.parseEther('0.005'));
    });

    it('should calculate correct BABL rewards in case of 1 strategy with total duration of 3 quarters', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const block = await ethers.provider.getBlock();
      const now = block.timestamp;

      const [long1] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);

      await finalizeStrategyAfter3Quarters(long1);
      const { exitedAt } = await getStrategyState(long1);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 4,
        timeListPointer: 1,
      });

      const valueLong1 = await getStrategyRewards(long1, now, 1, 4, [
        ethers.utils.parseEther('1'),
        ethers.utils.parseEther('1'),
        ethers.utils.parseEther('1'),
        ethers.utils.parseEther('1'),
      ]);
      const rewardsLong1 = await long1.strategyRewards();
      expect(rewardsLong1).to.be.closeTo(valueLong1, ethers.utils.parseEther('0.005'));

      expect(rewardsLong1).to.be.closeTo('143814823688624358512181', rewardsLong1.div(100));
    });

    it('should calculate correct BABL in case of 5 strategies of 2 different Gardens with different timings along 3 quarters', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const block = await ethers.provider.getBlock();
      const now = block.timestamp;

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
      await finalizeStrategyAfterQuarter(long3);
      await finalizeStrategyAfter2Quarters(long4);
      await finalizeStrategyAfter3Quarters(long5);
      const { exitedAt } = await getStrategyState(long5);

      await getAndValidateProtocolTimestampAndQuarter(rewardsDistributor, exitedAt, {
        principal: 0,
        quarter: 10,
        timeListPointer: 9,
      });
      const powerLong1 = [ethers.utils.parseEther('0.2053968535'), ethers.utils.parseEther('0.2000000000')];
      const powerLong2 = [
        ethers.utils.parseEther('0.2026984162'),
        ethers.utils.parseEther('0.2272712659'),
        ethers.utils.parseEther('0.25'),
        ethers.utils.parseEther('0.25'),
      ];
      const powerLong3 = [
        ethers.utils.parseEther('0.1999999946'),
        ethers.utils.parseEther('0.2272712659'),
        ethers.utils.parseEther('0.25'),
        ethers.utils.parseEther('0.2939547169'),
        ethers.utils.parseEther('0.3333333333'),
      ];
      const powerLong4 = [
        ethers.utils.parseEther('0.1973015731'),
        ethers.utils.parseEther('0.2272712659'),
        ethers.utils.parseEther('0.25'),
        ethers.utils.parseEther('0.2939547169'),
        ethers.utils.parseEther('0.4160182432'),
        ethers.utils.parseEther('0.5'),
        ethers.utils.parseEther('0.5'),
      ];
      const powerLong5 = [
        ethers.utils.parseEther('0.1946031516'),
        ethers.utils.parseEther('0.2272712659'),
        ethers.utils.parseEther('0.25'),
        ethers.utils.parseEther('0.2939547169'),
        ethers.utils.parseEther('0.4160182432'),
        ethers.utils.parseEther('0.5'),
        ethers.utils.parseEther('0.7114415557'),
        ethers.utils.parseEther('1'),
        ethers.utils.parseEther('1'),
        ethers.utils.parseEther('1'),
      ];

      const valueLong1 = await getStrategyRewards(long1, now, 1, 2, powerLong1);
      const valueLong2 = await getStrategyRewards(long2, now, 1, 4, powerLong2);
      const valueLong3 = await getStrategyRewards(long3, now, 1, 5, powerLong3);
      const valueLong4 = await getStrategyRewards(long4, now, 1, 7, powerLong4);
      const valueLong5 = await getStrategyRewards(long5, now, 1, 10, powerLong5);

      const rewardsLong1 = await long1.strategyRewards();
      const rewardsLong2 = await long2.strategyRewards();
      const rewardsLong3 = await long3.strategyRewards();
      const rewardsLong4 = await long4.strategyRewards();
      const rewardsLong5 = await long5.strategyRewards();

      expect(rewardsLong1).to.be.closeTo(valueLong1, valueLong1.div(100));
      expect(rewardsLong2).to.be.closeTo(valueLong2, valueLong2.div(100));
      expect(rewardsLong3).to.be.closeTo(valueLong3, valueLong3.div(100));
      expect(rewardsLong4).to.be.closeTo(valueLong4, valueLong4.div(100));
      expect(rewardsLong5).to.be.closeTo(valueLong5, valueLong5.div(100));
    });

    it('should calculate correct BABL (in 10 Years from now) in case of 5 strategies of 2 different Gardens with different timings along 3 quarters', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const block = await ethers.provider.getBlock();
      const now = block.timestamp;

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

      const powerLong1 = [ethers.utils.parseEther('0.2127901644'), ethers.utils.parseEther('0.2000000000')];
      const powerLong2 = [
        ethers.utils.parseEther('0.2063950695'),
        ethers.utils.parseEther('0.2017925594'),
        ethers.utils.parseEther('0.25'),
        ethers.utils.parseEther('0.25'),
      ];
      const powerLong3 = [
        ethers.utils.parseEther('0.1999999746'),
        ethers.utils.parseEther('0.2017925594'),
        ethers.utils.parseEther('0.25'),
        ethers.utils.parseEther('0.2526885858'),
        ethers.utils.parseEther('0.3333333333'),
      ];
      const powerLong4 = [
        ethers.utils.parseEther('0.1936049432'),
        ethers.utils.parseEther('0.2017925594'),
        ethers.utils.parseEther('0.25'),
        ethers.utils.parseEther('0.2526885858'),
        ethers.utils.parseEther('0.3379181444'),
        ethers.utils.parseEther('0.5'),
        ethers.utils.parseEther('0.5'),
      ];
      const powerLong5 = [
        ethers.utils.parseEther('0.1872098483'),
        ethers.utils.parseEther('0.2017925594'),
        ethers.utils.parseEther('0.25'),
        ethers.utils.parseEther('0.2526885858'),
        ethers.utils.parseEther('0.3379181444'),
        ethers.utils.parseEther('0.5'),
        ethers.utils.parseEther('0.5099042139'),
        ethers.utils.parseEther('1'),
        ethers.utils.parseEther('1'),
        ethers.utils.parseEther('1'),
      ];

      const valueLong1 = await getStrategyRewards(long1, now, 41, 42, powerLong1);
      const valueLong2 = await getStrategyRewards(long2, now, 41, 44, powerLong2);
      const valueLong3 = await getStrategyRewards(long3, now, 41, 45, powerLong3);
      const valueLong4 = await getStrategyRewards(long4, now, 41, 47, powerLong4);
      const valueLong5 = await getStrategyRewards(long5, now, 41, 50, powerLong5);

      const rewardsLong1 = await long1.strategyRewards();
      const rewardsLong2 = await long2.strategyRewards();
      const rewardsLong3 = await long3.strategyRewards();
      const rewardsLong4 = await long4.strategyRewards();
      const rewardsLong5 = await long5.strategyRewards();

      expect(rewardsLong1).to.be.closeTo(valueLong1, valueLong1.div(100));
      expect(rewardsLong2).to.be.closeTo(valueLong2, valueLong2.div(100));
      expect(rewardsLong3).to.be.closeTo(valueLong3, valueLong3.div(100));
      expect(rewardsLong4).to.be.closeTo(valueLong4, valueLong4.div(100));
      expect(rewardsLong5).to.be.closeTo(valueLong5, valueLong5.div(100));

      expect(rewardsLong1).to.be.closeTo('217227459687116953608', rewardsLong1.div(100));
      expect(rewardsLong2).to.be.closeTo('432866381321524321541', rewardsLong2.div(100));
      expect(rewardsLong3).to.be.closeTo('550877848075216077400', rewardsLong3.div(100));
      expect(rewardsLong4).to.be.closeTo('855311059338348715428', rewardsLong4.div(100));
      expect(rewardsLong5).to.be.closeTo('1548564705482122746208', rewardsLong5.div(100));
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

      const rewardsLong1 = await long1.strategyRewards();
      const rewardsLong2 = await long2.strategyRewards();
      const rewardsLong3 = await long3.strategyRewards();
      const rewardsLong4 = await long4.strategyRewards();
      const rewardsLong5 = await long5.strategyRewards();

      const rewards1 = parse('14507.72');
      const rewards2 = parse('36027.27');
      const rewards3 = parse('103496.84');
      const rewards4 = parse('116777.46');
      const rewards5 = parse('146632.70');

      expect(rewardsLong1).to.be.closeTo(rewards1, rewards1.div(50));
      expect(rewardsLong2).to.be.closeTo(rewards2, rewards2.div(50));
      expect(rewardsLong3).to.be.closeTo(rewards3, rewards3.div(50));
      expect(rewardsLong4).to.be.closeTo(rewards4, rewards4.div(50));
      expect(rewardsLong5).to.be.closeTo(rewards5, rewards5.div(50));
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

      const rewardsLong1 = await long1.strategyRewards();
      const rewardsLong2 = await long2.strategyRewards();
      const rewardsLong3 = await long3.strategyRewards();
      const rewardsLong4 = await long4.strategyRewards();
      const rewardsLong5 = await long5.strategyRewards();

      const rewards1 = parse('15411.51');
      const rewards2 = parse('36084.52');
      const rewards3 = parse('109290.88');
      const rewards4 = parse('123369.37');
      const rewards5 = parse('155795.75');

      expect(rewardsLong1).to.be.closeTo(rewards1, rewards1.div(50));
      expect(rewardsLong2).to.be.closeTo(rewards2, rewards2.div(50));
      expect(rewardsLong3).to.be.closeTo(rewards3, rewards3.div(50));
      expect(rewardsLong4).to.be.closeTo(rewards4, rewards4.div(50));
      expect(rewardsLong5).to.be.closeTo(rewards5, rewards5.div(50));
    });
  });

  describe('Capital reallocation and unwinding per garden-reserveAsset', function () {
    [
      { token: addresses.tokens.WETH, name: 'WETH' },
      //  { token: addresses.tokens.DAI, name: 'DAI' }, cannot trade the same asset DAI for DAI
      { token: addresses.tokens.USDC, name: 'USDC' },
      { token: addresses.tokens.WBTC, name: 'WBTC' },
    ].forEach(({ token, name }) => {
      it(`can reallocate and unwind capital of a strategy in a ${name} Garden`, async function () {
        // TODO update operation to use DAI
        // Mining program has to be enabled before the strategy starts its execution
        await babController.connect(owner).enableBABLMiningProgram();

        await transferFunds(token);

        const garden = await createGarden({ reserveAsset: token });
        await depositFunds(token, garden);
        const [strategyContract] = await createStrategies([{ garden: garden }]);

        const amount = STRATEGY_EXECUTE_MAP[token];

        await executeStrategy(strategyContract, { amount });
        const [preallocated, pricePerTokenUnit] = await rewardsDistributor.getStrategyPricePerTokenUnit(
          strategyContract.address,
        );

        expect(preallocated).to.be.equal(amount);
        const reserveAssetContract = await ethers.getContractAt(
          '@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20',
          token,
        );
        expect(await strategyContract.capitalAllocated()).to.equal(amount);
        await increaseTime(ONE_DAY_IN_SECONDS * 70);
        await increaseBlock(100);

        // We reallocate capital
        await executeStrategy(strategyContract, { amount: amount });
        const [preallocated1, pricePerTokenUnit1] = await rewardsDistributor.getStrategyPricePerTokenUnit(
          strategyContract.address,
        );
        expect(preallocated1).to.be.equal(amount.mul(2));
        expect(pricePerTokenUnit1).to.be.closeTo(pricePerTokenUnit, pricePerTokenUnit1.div(100));

        expect(await strategyContract.capitalAllocated()).to.equal(amount.mul(2));

        await increaseTime(ONE_DAY_IN_SECONDS * 70);
        await increaseBlock(50);
        // We unwind capital
        await strategyContract.connect(owner).unwindStrategy(amount);
        const [preallocated2, pricePerTokenUnit2] = await rewardsDistributor.getStrategyPricePerTokenUnit(
          strategyContract.address,
        );
        expect(preallocated2).to.be.closeTo(amount, preallocated2.div(100));
        expect(pricePerTokenUnit2).to.be.closeTo(pricePerTokenUnit, pricePerTokenUnit2.div(100));
        expect(await strategyContract.capitalAllocated()).to.equal(amount);

        await increaseTime(ONE_DAY_IN_SECONDS * 70);
        await increaseBlock(10);
        await finalizeStrategyAfter30Days(strategyContract);
        const [preallocated3, pricePerTokenUnit3] = await rewardsDistributor.getStrategyPricePerTokenUnit(
          strategyContract.address,
        );

        expect(preallocated3).to.be.equal(0);
        expect(pricePerTokenUnit3).to.be.closeTo(pricePerTokenUnit, pricePerTokenUnit3.div(100));
        expect(await reserveAssetContract.balanceOf(garden.address)).to.be.gte(amount);
      });
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

    it('should claim and update balances of Signer1 in DAI Garden as contributor of 1 strategy with profit within a quarter', async function () {
      const whaleAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'; // Has DAI
      const whaleSigner = await impersonateAddress(whaleAddress);
      await dai.connect(whaleSigner).transfer(signer1.address, ethers.utils.parseEther('5000'), {
        gasPrice: 0,
      });
      await dai.connect(whaleSigner).transfer(signer3.address, ethers.utils.parseEther('5000'), {
        gasPrice: 0,
      });
      await dai.connect(signer1).approve(babController.address, ethers.utils.parseEther('2000'), {
        gasPrice: 0,
      });
      await babController
        .connect(signer1)
        .createGarden(
          addresses.tokens.DAI,
          'Absolute DAI Return [beta]',
          'EYFA',
          'http...',
          0,
          GARDEN_PARAMS_STABLE,
          ethers.utils.parseEther('500'),
          [false, false, false],
          [0, 0, 0],
          {},
        );
      const gardens = await babController.getGardens();
      daiGarden = await ethers.getContractAt('Garden', gardens[4]);

      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, daiGarden.address, 1, { gasPrice: 0 });
      await dai.connect(signer3).approve(daiGarden.address, ethers.utils.parseEther('500'), { gasPrice: 0 });
      await daiGarden.connect(signer3).deposit(ethers.utils.parseEther('500'), 1, signer3.getAddress(), false);

      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const long1 = await createStrategy(
        'buy',
        'vote',
        [signer1, signer3],
        uniswapV3TradeIntegration.address,
        daiGarden,
        DAI_STRATEGY_PARAMS,
        [usdc.address, 0],
      );
      const signer1DAIBalance2 = await dai.balanceOf(signer1.address);
      await executeStrategy(long1, { amount: ethers.utils.parseEther('1000') });
      await injectFakeProfits(long1, ethers.BigNumber.from(200 * 1000000)); // Dai has 18 decimals, we add usdc (6 decimals) during strategy execution
      await finalizeStrategyAfterQuarter(long1);
      // Check pending rewards for users
      const signer1Rewards = await rewardsDistributor.getRewards(daiGarden.address, signer1.address, [long1.address]);
      const signer1BABL = signer1Rewards[5];
      const signer1Profit = signer1Rewards[6];
      // We claim our tokens and check that they are received properly
      await daiGarden.connect(signer1).claimReturns([long1.address]);
      // Check remaining rewards for users (if any)
      const signer1Rewards2 = await rewardsDistributor.getRewards(daiGarden.address, signer1.address, [long1.address]);
      const signer1BABL2 = signer1Rewards2[5];
      const signer1Profit2 = signer1Rewards2[6];
      const value = signer1DAIBalance2.add(signer1Profit);
      // LP profits
      // Receive BABL token after claim
      const signer1BalanceBABL = await bablToken.balanceOf(signer1.address);
      expect(signer1BalanceBABL).to.be.closeTo(signer1BABL, ethers.utils.parseEther('0.000005'));
      // Receive DAI as strategist and steward directly in its wallet after claim
      const signer1BalanceDAI = await dai.balanceOf(signer1.address);
      expect(signer1BalanceDAI).to.equal(value);
      // Automatically get DAI profit as LP in its garden balance when strategy finalizes
      expect(signer1Profit2).to.equal('0');
      expect(signer1BABL2).to.equal('0');
    });
    it('should claim and update balances of Signer1 in USDC Garden as contributor of 1 strategy with profit within a quarter', async function () {
      const whaleAddress = '0x0a59649758aa4d66e25f08dd01271e891fe52199'; // Has USDC
      const whaleSigner = await impersonateAddress(whaleAddress);
      const thousandUSDC = ethers.BigNumber.from(1e4 * 1e6);

      await usdc.connect(whaleSigner).transfer(signer1.address, thousandUSDC, {
        gasPrice: 0,
      });
      await usdc.connect(whaleSigner).transfer(signer3.address, thousandUSDC, {
        gasPrice: 0,
      });
      await usdc.connect(signer1).approve(babController.address, thousandUSDC, {
        gasPrice: 0,
      });
      const params = [...USDC_GARDEN_PARAMS];
      params[3] = thousandUSDC.div(10);
      await babController
        .connect(signer1)
        .createGarden(
          addresses.tokens.USDC,
          'Absolute USDC Return [beta]',
          'EYFA',
          'http...',
          0,
          params,
          thousandUSDC.div(2),
          [false, false, false],
          [0, 0, 0],
          {},
        );
      const gardens = await babController.getGardens();
      usdcGarden = await ethers.getContractAt('Garden', gardens[4]);

      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, usdcGarden.address, 1, { gasPrice: 0 });
      await usdc.connect(signer3).approve(usdcGarden.address, thousandUSDC, { gasPrice: 0 });
      await usdcGarden.connect(signer3).deposit(thousandUSDC.div(2), 1, signer3.getAddress(), false);

      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

      const long1 = await createStrategy(
        'buy',
        'vote',
        [signer1, signer3],
        masterSwapper.address,
        usdcGarden,
        USDC_STRATEGY_PARAMS,
        [dai.address, 0],
      );
      // TODO Check masterswapper fails with weth, address(0) and (usdc)
      const signer1USDCBalance2 = await usdc.balanceOf(signer1.address);
      await executeStrategy(long1, { amount: ethers.BigNumber.from(500 * 1000000) });
      await injectFakeProfits(long1, ethers.utils.parseEther('0.025')); // Using fake 18 decimals during the strategy execution

      await finalizeStrategyAfterQuarter(long1);
      // Check pending rewards for users
      const signer1Rewards = await rewardsDistributor.getRewards(usdcGarden.address, signer1.address, [long1.address]);
      const signer1BABL = signer1Rewards[5];
      const signer1Profit = signer1Rewards[6];
      // We claim our tokens and check that they are received properly
      await usdcGarden.connect(signer1).claimReturns([long1.address]);
      // Check remaining rewards for users (if any)
      const signer1Rewards2 = await rewardsDistributor.getRewards(usdcGarden.address, signer1.address, [long1.address]);
      const signer1BABL2 = signer1Rewards2[5];
      const signer1Profit2 = signer1Rewards2[6];
      const value = signer1USDCBalance2.add(signer1Profit);
      // LP profits
      // Receive BABL token after claim
      const signer1BalanceBABL = await bablToken.balanceOf(signer1.address);
      expect(signer1BalanceBABL).to.be.closeTo(signer1BABL, ethers.utils.parseEther('0.000005'));
      // Receive USDC as strategist and steward directly in its wallet after claim
      const signer1BalanceUSDC = await usdc.balanceOf(signer1.address);
      expect(signer1BalanceUSDC).to.equal(value);
      // Automatically get USDC profit as LP in its garden balance when strategy finalizes

      expect(signer1Profit2).to.equal('0');
      expect(signer1BABL2).to.equal('0');
    });
    it('should claim and update BABL Rewards of Signer1 in USDC Garden and DAI Garden as contributor of 2 strategies in 2 different gardens with profit within a quarter', async function () {
      const whaleAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'; // Has DAI
      const whaleSigner = await impersonateAddress(whaleAddress);
      await dai.connect(whaleSigner).transfer(signer1.address, ethers.utils.parseEther('5000'), {
        gasPrice: 0,
      });
      await dai.connect(whaleSigner).transfer(signer3.address, ethers.utils.parseEther('5000'), {
        gasPrice: 0,
      });
      await dai.connect(signer1).approve(babController.address, ethers.utils.parseEther('2000'), {
        gasPrice: 0,
      });

      const whaleAddress2 = '0x0a59649758aa4d66e25f08dd01271e891fe52199'; // Has USDC
      const whaleSigner2 = await impersonateAddress(whaleAddress2);
      const thousandUSDC = ethers.BigNumber.from(1e4 * 1e6);

      await usdc.connect(whaleSigner2).transfer(signer1.address, thousandUSDC, {
        gasPrice: 0,
      });
      await usdc.connect(whaleSigner2).transfer(signer3.address, thousandUSDC, {
        gasPrice: 0,
      });
      await usdc.connect(signer1).approve(babController.address, thousandUSDC, {
        gasPrice: 0,
      });
      const params = [...USDC_GARDEN_PARAMS];
      params[3] = thousandUSDC.div(10);
      // USC Garden
      await babController
        .connect(signer1)
        .createGarden(
          addresses.tokens.USDC,
          'Absolute USDC Return [beta]',
          'EYFA',
          'http...',
          0,
          params,
          thousandUSDC.div(2),
          [false, false, false],
          [0, 0, 0],
          {},
        );
      const gardens = await babController.getGardens();
      usdcGarden = await ethers.getContractAt('Garden', gardens[4]);

      // DAI Garden
      await babController
        .connect(signer1)
        .createGarden(
          addresses.tokens.DAI,
          'Absolute DAI Return [beta]',
          'EYFA',
          'http...',
          0,
          GARDEN_PARAMS_STABLE,
          ethers.utils.parseEther('500'),
          [false, false, false],
          [0, 0, 0],
          {},
        );
      const gardens2 = await babController.getGardens();
      daiGarden = await ethers.getContractAt('Garden', gardens2[5]);

      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, daiGarden.address, 1, { gasPrice: 0 });
      await dai.connect(signer3).approve(daiGarden.address, ethers.utils.parseEther('500'), { gasPrice: 0 });
      await daiGarden.connect(signer3).deposit(ethers.utils.parseEther('500'), 1, signer3.getAddress(), false);

      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, usdcGarden.address, 1, { gasPrice: 0 });
      await usdc.connect(signer3).approve(usdcGarden.address, thousandUSDC, { gasPrice: 0 });
      await usdcGarden.connect(signer3).deposit(thousandUSDC.div(2), 1, signer3.getAddress(), false);

      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const long1 = await createStrategy(
        'buy',
        'vote',
        [signer1, signer3],
        uniswapV3TradeIntegration.address,
        usdcGarden,
        USDC_STRATEGY_PARAMS,
        [dai.address, 0],
      );

      const long2 = await createStrategy(
        'buy',
        'vote',
        [signer1, signer3],
        uniswapV3TradeIntegration.address,
        daiGarden,
        DAI_STRATEGY_PARAMS,
        [usdc.address, 0],
      );
      // Execute USDC Garden strategy long1
      await executeStrategy(long1, { amount: ethers.BigNumber.from(1000 * 1000000) });

      // Execute DAI Garden strategy long2
      await executeStrategy(long2, { amount: ethers.utils.parseEther('1000') });
      await injectFakeProfits(long1, ethers.utils.parseEther('200')); // injecting DAI (18 decimals)
      await injectFakeProfits(long2, ethers.BigNumber.from(200 * 1000000)); // injecting USDC (6 decimals)
      // Finalize both strategies (long 2 has higher duration -> more rewardss)
      await finalizeStrategyAfterQuarter(long1);
      await finalizeStrategyImmediate(long2);
      // Check pending rewards for users at USDC Garden
      const signer1RewardsUSDC = await rewardsDistributor.getRewards(usdcGarden.address, signer1.address, [
        long1.address,
      ]);
      const signer1BABLUSDC = signer1RewardsUSDC[5];

      // Check pending rewards for users at DAI Garden
      const signer1RewardsDAI = await rewardsDistributor.getRewards(daiGarden.address, signer1.address, [
        long2.address,
      ]);
      const signer1BABLDAI = signer1RewardsDAI[5];

      // We claim our tokens and check that they are received properly
      await usdcGarden.connect(signer1).claimReturns([long1.address]);

      // We claim our tokens and check that they are received properly
      await daiGarden.connect(signer1).claimReturns([long2.address]);
      // Receive BABL token after claim
      const signer1BalanceBABL = await bablToken.balanceOf(signer1.address);
      expect(signer1BalanceBABL).to.be.closeTo(signer1BABLUSDC.add(signer1BABLDAI), ethers.utils.parseEther('0.0005'));
      expect(signer1BABLUSDC).to.be.closeTo(signer1BABLDAI, signer1BABLDAI.div(50));
    });
    it('should provide correct % of strategy rewards per profile with profits', async function () {
      const whaleAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'; // Has DAI
      const whaleSigner = await impersonateAddress(whaleAddress);
      await dai.connect(whaleSigner).transfer(signer1.address, ethers.utils.parseEther('5000'), {
        gasPrice: 0,
      });
      await dai.connect(whaleSigner).transfer(signer3.address, ethers.utils.parseEther('5000'), {
        gasPrice: 0,
      });
      await dai.connect(signer1).approve(babController.address, ethers.utils.parseEther('2000'), {
        gasPrice: 0,
      });
      const whaleAddress2 = '0x0A59649758aa4d66E25f08Dd01271e891fe52199'; // Has USDC
      const whaleSigner2 = await impersonateAddress(whaleAddress2);
      const thousandUSDC = ethers.BigNumber.from(1e4 * 1e6);

      await usdc.connect(whaleSigner2).transfer(signer1.address, thousandUSDC, {
        gasPrice: 0,
      });
      await usdc.connect(whaleSigner2).transfer(signer3.address, thousandUSDC, {
        gasPrice: 0,
      });
      await usdc.connect(signer1).approve(babController.address, thousandUSDC, {
        gasPrice: 0,
      });
      const params = [...USDC_GARDEN_PARAMS];
      params[3] = thousandUSDC.div(10);
      // USC Garden
      await babController.connect(signer1).createGarden(
        addresses.tokens.USDC,
        'Absolute USDC Return [beta]',
        'EYFA',
        'http...',
        0,
        params,
        thousandUSDC.div(2),
        [false, false, false],
        // Note there are no profits for stewards or LP (95% for strategist)
        [ethers.utils.parseEther('0.95'), ethers.utils.parseEther('0'), ethers.utils.parseEther('0')],
        {},
      );
      const gardens = await babController.getGardens();
      usdcGarden = await ethers.getContractAt('Garden', gardens[4]);

      // DAI Garden
      await babController.connect(signer1).createGarden(
        addresses.tokens.DAI,
        'Absolute DAI Return [beta]',
        'EYFA',
        'http...',
        0,
        GARDEN_PARAMS_STABLE,
        ethers.utils.parseEther('500'),
        [false, false, false],
        // Note there are no profits for stewards or LP (95% for strategist)
        [ethers.utils.parseEther('0'), ethers.utils.parseEther('0.95'), ethers.utils.parseEther('0')],
        {},
      );
      const gardens2 = await babController.getGardens();
      daiGarden = await ethers.getContractAt('Garden', gardens2[5]);

      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, daiGarden.address, 1, { gasPrice: 0 });
      await dai.connect(signer3).approve(daiGarden.address, ethers.utils.parseEther('500'), { gasPrice: 0 });
      await daiGarden.connect(signer3).deposit(ethers.utils.parseEther('500'), 1, signer3.getAddress(), false);

      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, usdcGarden.address, 1, { gasPrice: 0 });
      await usdc.connect(signer3).approve(usdcGarden.address, thousandUSDC, { gasPrice: 0 });
      await usdcGarden.connect(signer3).deposit(thousandUSDC.div(2), 1, signer3.getAddress(), false);

      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const long1 = await createStrategy(
        'buy',
        'vote',
        [signer1, signer3],
        masterSwapper.address,
        usdcGarden,
        USDC_STRATEGY_PARAMS,
        [dai.address, 0],
      );

      const long2 = await createStrategy(
        'buy',
        'vote',
        [signer1, signer3],
        masterSwapper.address,
        daiGarden,
        DAI_STRATEGY_PARAMS,
        [usdc.address, 0],
      );
      // Execute USDC Garden strategy long1
      await executeStrategy(long1, { amount: ethers.BigNumber.from(1000 * 1000000) });
      // Execute DAI Garden strategy long2
      await executeStrategy(long2, { amount: ethers.utils.parseEther('1000') });
      await injectFakeProfits(long1, ethers.utils.parseEther('200')); // inject 200 DAI (19 decimals)
      await injectFakeProfits(long2, ethers.BigNumber.from(200 * 1000000)); // inject 200 USDC (6 decimals)
      // Finalize both strategies (long 2 has higher duration -> more rewardss)
      await finalizeStrategyAfterQuarter(long1);
      await finalizeStrategyImmediate(long2);
      // Check pending rewards for users at USDC Garden
      const signer1RewardsUSDC = await rewardsDistributor.getRewards(usdcGarden.address, signer1.address, [
        long1.address,
      ]);
      const signer3RewardsUSDC = await rewardsDistributor.getRewards(usdcGarden.address, signer3.address, [
        long1.address,
      ]);
      const signer1ProfitUSDC = signer1RewardsUSDC[6];
      const signer3ProfitUSDC = signer3RewardsUSDC[6];
      // Check pending rewards for users at DAI Garden
      const signer1RewardsDAI = await rewardsDistributor.getRewards(daiGarden.address, signer1.address, [
        long2.address,
      ]);
      const signer3RewardsDAI = await rewardsDistributor.getRewards(daiGarden.address, signer3.address, [
        long2.address,
      ]);
      const signer1ProfitDAI = signer1RewardsDAI[6];
      const signer3ProfitDAI = signer3RewardsDAI[6];
      // USDC Garden is set up to give all profit rewards to strategist
      // so signer 3 despite is LP and steward but gets no (0) profits
      await expect(signer3ProfitUSDC).to.equal(0);
      await expect(signer1ProfitUSDC).to.equal(179962394);
      // DAI Garden is set up to give all profit rewards to stewards
      // so signer 1 despite is the strategist gets the same profits than signer3
      await expect(signer1ProfitDAI).to.equal(signer3ProfitDAI);
    });
    it('should claim and update BABL Rewards of Signer1 in USDC Garden and DAI Garden as contributor of 2 strategies in 2 different gardens with profit below expected return within a quarter', async function () {
      const whaleAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'; // Has DAI
      const whaleSigner = await impersonateAddress(whaleAddress);
      await dai.connect(whaleSigner).transfer(signer1.address, ethers.utils.parseEther('5000'), {
        gasPrice: 0,
      });
      await dai.connect(whaleSigner).transfer(signer3.address, ethers.utils.parseEther('5000'), {
        gasPrice: 0,
      });
      await dai.connect(signer1).approve(babController.address, ethers.utils.parseEther('2000'), {
        gasPrice: 0,
      });

      const whaleAddress2 = '0x0a59649758aa4d66e25f08dd01271e891fe52199'; // Has USDC
      const whaleSigner2 = await impersonateAddress(whaleAddress2);
      const thousandUSDC = ethers.BigNumber.from(1e4 * 1e6);

      await usdc.connect(whaleSigner2).transfer(signer1.address, thousandUSDC, {
        gasPrice: 0,
      });
      await usdc.connect(whaleSigner2).transfer(signer3.address, thousandUSDC, {
        gasPrice: 0,
      });
      await usdc.connect(signer1).approve(babController.address, thousandUSDC, {
        gasPrice: 0,
      });
      const params = [...USDC_GARDEN_PARAMS];
      params[3] = thousandUSDC.div(10);
      // USC Garden
      await babController
        .connect(signer1)
        .createGarden(
          addresses.tokens.USDC,
          'Absolute USDC Return [beta]',
          'EYFA',
          'http...',
          0,
          params,
          thousandUSDC.div(2),
          [false, false, false],
          [0, 0, 0],
          {},
        );
      const gardens = await babController.getGardens();
      usdcGarden = await ethers.getContractAt('Garden', gardens[4]);

      // DAI Garden
      await babController
        .connect(signer1)
        .createGarden(
          addresses.tokens.DAI,
          'Absolute DAI Return [beta]',
          'EYFA',
          'http...',
          0,
          GARDEN_PARAMS_STABLE,
          ethers.utils.parseEther('500'),
          [false, false, false],
          [0, 0, 0],
          {},
        );
      const gardens2 = await babController.getGardens();
      daiGarden = await ethers.getContractAt('Garden', gardens2[5]);

      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, daiGarden.address, 1, { gasPrice: 0 });
      await dai.connect(signer3).approve(daiGarden.address, ethers.utils.parseEther('500'), { gasPrice: 0 });
      await daiGarden.connect(signer3).deposit(ethers.utils.parseEther('500'), 1, signer3.getAddress(), false);

      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, usdcGarden.address, 1, { gasPrice: 0 });
      await usdc.connect(signer3).approve(usdcGarden.address, thousandUSDC, { gasPrice: 0 });
      await usdcGarden.connect(signer3).deposit(thousandUSDC.div(2), 1, signer3.getAddress(), false);

      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const long1 = await createStrategy(
        'buy',
        'vote',
        [signer1, signer3],
        masterSwapper.address,
        usdcGarden,
        USDC_STRATEGY_PARAMS,
        [dai.address, 0],
      );

      const long2 = await createStrategy(
        'buy',
        'vote',
        [signer1, signer3],
        masterSwapper.address,
        daiGarden,
        DAI_STRATEGY_PARAMS,
        [usdc.address, 0],
      );
      // Execute USDC Garden strategy long1
      await executeStrategy(long1, { amount: ethers.BigNumber.from(1000 * 1000000) });

      // Execute DAI Garden strategy long2
      await executeStrategy(long2, { amount: ethers.utils.parseEther('1000') });

      await injectFakeProfits(long1, ethers.utils.parseEther('20')); // Using fake 18 decimals during the strategy execution
      await injectFakeProfits(long2, ethers.BigNumber.from(20 * 1000000)); // Dai has 18 decimals, we add usdc (6 decimals) during strategy execution

      // Finalize both strategies (long 2 has higher duration -> more rewardss)
      await finalizeStrategyAfterQuarter(long1);
      await finalizeStrategyImmediate(long2);

      // Check pending rewards for users at USDC Garden
      const signer1RewardsUSDC = await rewardsDistributor.getRewards(usdcGarden.address, signer1.address, [
        long1.address,
      ]);
      const signer1BABLUSDC = signer1RewardsUSDC[5];

      // Check pending rewards for users at DAI Garden
      const signer1RewardsDAI = await rewardsDistributor.getRewards(daiGarden.address, signer1.address, [
        long2.address,
      ]);
      const signer1BABLDAI = signer1RewardsDAI[5];

      // We claim our tokens and check that they are received properly
      await usdcGarden.connect(signer1).claimReturns([long1.address]);

      // We claim our tokens and check that they are received properly
      await daiGarden.connect(signer1).claimReturns([long2.address]);

      // Receive BABL token after claim
      const signer1BalanceBABL = await bablToken.balanceOf(signer1.address);
      expect(signer1BalanceBABL).to.be.closeTo(
        signer1BABLUSDC.add(signer1BABLDAI),
        ethers.utils.parseEther('0.000005'),
      );
    });
    it('should claim and update BABL Rewards of Signer1 in USDC Garden and DAI Garden as contributor of 2 strategies in 2 different gardens without profit within a quarter', async function () {
      const whaleAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'; // Has DAI
      const whaleSigner = await impersonateAddress(whaleAddress);
      await dai.connect(whaleSigner).transfer(signer1.address, ethers.utils.parseEther('5000'), {
        gasPrice: 0,
      });
      await dai.connect(whaleSigner).transfer(signer3.address, ethers.utils.parseEther('5000'), {
        gasPrice: 0,
      });
      await dai.connect(signer1).approve(babController.address, ethers.utils.parseEther('2000'), {
        gasPrice: 0,
      });

      const whaleAddress2 = '0x0a59649758aa4d66e25f08dd01271e891fe52199'; // Has USDC
      const whaleSigner2 = await impersonateAddress(whaleAddress2);
      const thousandUSDC = ethers.BigNumber.from(1e4 * 1e6);

      await usdc.connect(whaleSigner2).transfer(signer1.address, thousandUSDC, {
        gasPrice: 0,
      });
      await usdc.connect(whaleSigner2).transfer(signer3.address, thousandUSDC, {
        gasPrice: 0,
      });
      await usdc.connect(signer1).approve(babController.address, thousandUSDC, {
        gasPrice: 0,
      });
      const params = [...USDC_GARDEN_PARAMS];
      params[3] = thousandUSDC.div(10);
      // USC Garden
      await babController
        .connect(signer1)
        .createGarden(
          addresses.tokens.USDC,
          'Absolute USDC Return [beta]',
          'EYFA',
          'http...',
          0,
          params,
          thousandUSDC.div(2),
          [false, false, false],
          [0, 0, 0],
          {},
        );
      const gardens = await babController.getGardens();
      usdcGarden = await ethers.getContractAt('Garden', gardens[4]);

      // DAI Garden
      await babController
        .connect(signer1)
        .createGarden(
          addresses.tokens.DAI,
          'Absolute DAI Return [beta]',
          'EYFA',
          'http...',
          0,
          GARDEN_PARAMS_STABLE,
          ethers.utils.parseEther('500'),
          [false, false, false],
          [0, 0, 0],
          {},
        );
      const gardens2 = await babController.getGardens();
      daiGarden = await ethers.getContractAt('Garden', gardens2[5]);

      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, daiGarden.address, 1, { gasPrice: 0 });
      await dai.connect(signer3).approve(daiGarden.address, ethers.utils.parseEther('500'), { gasPrice: 0 });
      await daiGarden.connect(signer3).deposit(ethers.utils.parseEther('500'), 1, signer3.getAddress(), false);

      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, usdcGarden.address, 1, { gasPrice: 0 });
      await usdc.connect(signer3).approve(usdcGarden.address, thousandUSDC, { gasPrice: 0 });
      await usdcGarden.connect(signer3).deposit(thousandUSDC.div(2), 1, signer3.getAddress(), false);

      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();
      const long1 = await createStrategy(
        'buy',
        'vote',
        [signer1, signer3],
        uniswapV3TradeIntegration.address,
        usdcGarden,
        USDC_STRATEGY_PARAMS,
        [weth.address, 0],
      );

      const long2 = await createStrategy(
        'buy',
        'vote',
        [signer1, signer3],
        uniswapV3TradeIntegration.address,
        daiGarden,
        DAI_STRATEGY_PARAMS,
        [usdc.address, 0],
      );
      // Execute USDC Garden strategy long1
      await executeStrategy(long1, { amount: ethers.BigNumber.from(1000 * 1000000) });

      // Execute DAI Garden strategy long2
      await executeStrategy(long2, { amount: ethers.utils.parseEther('1000') });

      await substractFakeProfits(long1, ethers.utils.parseEther('0.0025')); // Using fake 18 decimals during the strategy execution
      await substractFakeProfits(long2, ethers.BigNumber.from(20 * 1000000)); // Dai has 18 decimals, we add usdc (6 decimals) during strategy execution

      // Finalize both strategies (long 2 has higher duration -> more rewardss)
      await finalizeStrategyAfterQuarter(long1);
      await finalizeStrategyImmediate(long2);

      // Check pending rewards for users at USDC Garden
      const signer1RewardsUSDC = await rewardsDistributor.getRewards(usdcGarden.address, signer1.address, [
        long1.address,
      ]);
      const signer1BABLStrategistUSDC = signer1RewardsUSDC[0];
      const signer1BABLStewardUSDC = signer1RewardsUSDC[2];
      expect(signer1BABLStrategistUSDC).to.equal(0);
      expect(signer1BABLStewardUSDC).to.equal(0);

      const signer1BABLUSDC = signer1RewardsUSDC[5];

      // Check pending rewards for users at DAI Garden
      const signer1RewardsDAI = await rewardsDistributor.getRewards(daiGarden.address, signer1.address, [
        long2.address,
      ]);
      const signer1BABLStrategistDAI = signer1RewardsDAI[0];
      const signer1BABLStewardDAI = signer1RewardsDAI[2];
      expect(signer1BABLStrategistDAI).to.equal(0);
      expect(signer1BABLStewardDAI).to.equal(0);

      const signer1BABLDAI = signer1RewardsDAI[5];

      // We claim our tokens and check that they are received properly
      await usdcGarden.connect(signer1).claimReturns([long1.address]);

      // We claim our tokens and check that they are received properly
      await daiGarden.connect(signer1).claimReturns([long2.address]);

      // Receive BABL token after claim
      const signer1BalanceBABL = await bablToken.balanceOf(signer1.address);
      expect(signer1BalanceBABL).to.be.closeTo(signer1BABLUSDC.add(signer1BABLDAI), ethers.utils.parseEther('0.00005'));
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
      const signer1Rewards = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);
      const signer1BABL = signer1Rewards[5];
      const signer2Rewards = await rewardsDistributor.getRewards(garden1.address, signer2.address, [
        long1.address,
        long2.address,
      ]);
      const signer2BABL = signer2Rewards[5];
      // Balances before claiming
      const signer1GardenBalance = await garden1.balanceOf(signer1.address);
      const signer2GardenBalance = await garden1.balanceOf(signer2.address);

      expect((await bablToken.balanceOf(signer1.address)).toString()).to.be.equal('0');
      expect((await bablToken.balanceOf(signer2.address)).toString()).to.be.equal('0');

      // Signer1 claims its tokens and check that they are received properly
      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);
      const contributor = await garden1.getContributor(signer1.address);

      // Try again to claims the same tokens but no more tokens are delivered
      await expect(garden1.connect(signer1).claimReturns([long1.address, long2.address])).to.be.revertedWith('BAB#082');
      const contributor2 = await garden1.getContributor(signer1.address);

      await expect(contributor2[4].toString()).to.be.closeTo(contributor[4], ethers.utils.parseEther('0.00005'));

      // Signer2 claims his tokens and check that they are received properly
      await garden1.connect(signer2).claimReturns([long1.address, long2.address]);
      const contributor3 = await garden1.getContributor(signer2.address);
      // Try again to claims the same tokens but as there are no more tokens or rewards, it reverts
      await expect(garden1.connect(signer2).claimReturns([long1.address, long2.address])).to.be.revertedWith('BAB#082');
      const contributor4 = await garden1.getContributor(signer2.address);

      await expect(contributor4[4].toString()).to.be.closeTo(contributor3[4], ethers.utils.parseEther('0.00005'));

      // Check pending rewards for users (shouldn´t be any as they are already claimed)

      const signer1Rewards2 = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);
      const signer1BABL2 = signer1Rewards2[5];
      const signer1Profits2 = signer1Rewards2[6];

      const signer2Rewards2 = await rewardsDistributor.getRewards(garden1.address, signer2.address, [
        long1.address,
        long2.address,
      ]);
      const signer2BABL2 = signer2Rewards2[5];
      const signer2Profits2 = signer2Rewards2[6];

      expect(signer1Profits2.toString()).to.be.equal('0');
      expect(signer1BABL2.toString()).to.be.equal('0');
      expect(signer2Profits2.toString()).to.be.equal('0');
      expect(signer2BABL2.toString()).to.be.equal('0');

      expect((await bablToken.balanceOf(signer1.address)).toString()).to.be.closeTo(
        signer1BABL,
        ethers.utils.parseEther('0.005'),
      );
      expect((await bablToken.balanceOf(signer2.address)).toString()).to.be.closeTo(
        signer2BABL,
        ethers.utils.parseEther('0.005'),
      );
      expect((await garden1.balanceOf(signer1.address)).toString()).to.be.equal(signer1GardenBalance);
      expect((await garden1.balanceOf(signer2.address)).toString()).to.be.equal(signer2GardenBalance);
    });

    it('should only provide new additional BABL and profits between claims (claiming results of 2 strategies only 1 with profit)', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await injectFakeProfits(long1, ONE_ETH.mul(240));
      await finalizeStrategyAfterQuarter(long1);

      expect((await bablToken.balanceOf(signer1.address)).toString()).to.be.equal('0');

      const signer1Rewards = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);
      const signer1BABL = signer1Rewards[5];
      const signer1Profit = signer1Rewards[6];
      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);
      expect((await bablToken.balanceOf(signer1.address)).toString()).to.be.closeTo(
        signer1BABL,
        ethers.utils.parseEther('0.0005'),
      );
      expect(signer1Profit.toString()).to.be.closeTo('11985706580696756', ethers.utils.parseEther('0.0005'));
      const signer1Rewards2 = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);
      const signer1BABL2 = signer1Rewards2[5];
      const signer1Profit2 = signer1Rewards2[6];
      expect(signer1Profit2.toString()).to.be.equal('0');
      expect(signer1BABL2.toString()).to.be.equal('0');
      increaseTime(ONE_DAY_IN_SECONDS * 10);

      await finalizeStrategyAfterQuarter(long2);
      const signer1Rewards3 = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);
      const signer1BABL3 = signer1Rewards3[5];
      const signer1Profit3 = signer1Rewards3[6];

      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);
      expect(signer1Profit3.toString()).to.be.equal('0'); // Negative profit means no profit at all
      expect(signer1BABL3.toString()).to.be.closeTo('37701789043050854045289', signer1BABL3.div(100));
    });

    it('should only provide new additional BABL and profits between claims (claiming results of 2 strategies both with profit)', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await injectFakeProfits(long1, ONE_ETH.mul(240));
      await finalizeStrategyAfterQuarter(long1);

      console.log('---CHECK 1---');

      const signer1Rewards = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);
      const signer1BABL = signer1Rewards[5];
      const signer1Profit = signer1Rewards[6];
      console.log('---CHECK 2---');

      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);
      console.log('---CHECK 3---');

      await injectFakeProfits(long2, ONE_ETH.mul(240));
      await finalizeStrategyAfterQuarter(long2);
      const signer1Rewards2 = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);
      console.log('---CHECK 4---');

      const signer1BABL2 = signer1Rewards2[5];
      const signer1Profit2 = signer1Rewards2[6];

      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);
      expect(signer1Profit.toString()).to.be.not.equal(signer1Profit2);
      console.log('---CHECK 5---');

      expect(signer1Profit).to.be.closeTo('7393982129520472', signer1Profit.div(100));
      expect(signer1Profit2).to.be.closeTo('7264213370295943', signer1Profit2.div(100));

      expect((await bablToken.balanceOf(signer1.address)).toString()).to.be.closeTo(
        signer1BABL.add(signer1BABL2),
        ethers.utils.parseEther('0.0005'),
      );
    });

    it('should check potential claim values of Profit and BABL Rewards', async function () {
      // Mining program has to be enabled before the strategy starts its execution
      await babController.connect(owner).enableBABLMiningProgram();

      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH.mul(2));

      await injectFakeProfits(long1, ONE_ETH.mul(240));
      await finalizeStrategyAfterQuarter(long1);

      await injectFakeProfits(long2, ONE_ETH.mul(240));
      await finalizeStrategyAfterQuarter(long2);
      const signer1Rewards = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);
      const signer1BABL = signer1Rewards[5];
      const signer1Profit = signer1Rewards[6];
      // TODO: Add calculations of profits and BABL
      expect(signer1Profit).to.be.closeTo('14658195499816415', signer1Profit.div(100));
      expect(signer1BABL).to.be.closeTo('83465698586246333338582', signer1BABL.div(100));
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

      await injectFakeProfits(long1, ONE_ETH.mul(120));
      await finalizeStrategyAfterQuarter(long1);

      await finalizeStrategyAfter2Quarters(long2);

      await injectFakeProfits(long3, ONE_ETH.mul(120));
      await finalizeStrategyAfter2Years(long3);

      await injectFakeProfits(long4, ONE_ETH.mul(142));
      await finalizeStrategyAfter2Quarters(long4);

      await injectFakeProfits(long5, ONE_ETH.mul(142));
      await finalizeStrategyAfter3Quarters(long5);

      // We claim our tokens and check that they are received properly
      const signer1Rewards = await rewardsDistributor.getRewards(garden1.address, signer1.address, [
        long1.address,
        long2.address,
      ]);
      const signer1BABL = signer1Rewards[5];
      const signer1Profit = signer1Rewards[6];
      const signer2Rewards = await rewardsDistributor.getRewards(garden1.address, signer2.address, [
        long1.address,
        long2.address,
      ]);
      const signer2BABL = signer2Rewards[5];
      const signer2Profit = signer2Rewards[6];

      await garden1.connect(signer1).claimReturns([long1.address, long2.address]);
      await garden1.connect(signer2).claimReturns([long1.address, long2.address]);

      expect((await bablToken.balanceOf(signer1.address)).toString()).to.be.closeTo(
        signer1BABL,
        ethers.utils.parseEther('0.0005'),
      );
      expect((await bablToken.balanceOf(signer2.address)).toString()).to.be.closeTo(
        signer2BABL,
        ethers.utils.parseEther('0.0005'),
      );
      expect(signer1Profit.toString()).to.be.closeTo('5661673429627975', ethers.utils.parseEther('0.0005'));
      expect(signer2Profit.toString()).to.be.closeTo('871026681481226', ethers.utils.parseEther('0.0005'));
      const signer1Rewards2 = await rewardsDistributor.getRewards(garden2.address, signer1.address, [
        long3.address,
        long4.address,
        long5.address,
      ]);
      const signer1BABL2 = signer1Rewards2[5];
      const signer1Profit2 = signer1Rewards2[6];

      const signer2Rewards2 = await rewardsDistributor.getRewards(garden2.address, signer2.address, [
        long3.address,
        long4.address,
        long5.address,
      ]);
      const signer2BABL2 = signer2Rewards2[5];
      const signer2Profit2 = signer2Rewards2[6];

      await garden2.connect(signer1).claimReturns([long3.address, long4.address, long5.address]);
      await garden2.connect(signer2).claimReturns([long3.address, long4.address, long5.address]);

      expect((await bablToken.balanceOf(signer1.address)).toString()).to.be.closeTo(
        signer1BABL2.add(signer1BABL),
        ethers.utils.parseEther('0.005'),
      );
      expect((await bablToken.balanceOf(signer2.address)).toString()).to.be.closeTo(
        signer2BABL2.add(signer2BABL),
        ethers.utils.parseEther('0.005'),
      );

      expect(signer1Profit2.toString()).to.be.closeTo('19132336437560088', ethers.utils.parseEther('0.0005'));
      expect(signer2Profit2.toString()).to.be.closeTo('3135337489180200', ethers.utils.parseEther('0.0005'));
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
      ).to.be.revertedWith('BAB#073');
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
      ).to.be.revertedWith('BAB#073');
    });
  });
});
