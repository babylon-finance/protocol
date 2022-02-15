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
const { ONE_DAY_IN_SECONDS } = require('lib/constants.js');
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
  let strategyDataset;
  let strategyCandidate;
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

  beforeEach(async () => {
    ({
      owner,
      keeper,
      babController,
      signer1,
      garden1,
      garden2,
      treasury,
      heart,
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
      masterSwapper,
      weth,
    } = await setupTests()());

    strategyDataset = await ethers.getContractAt('Strategy', strategy11);
    strategyCandidate = await ethers.getContractAt('Strategy', strategy21);

    wethToken = await getERC20(addresses.tokens.WETH);
  });

  describe('addStrategy', async function () {
    it('should NOT initialize a strategy with maxcapitalrequested of 0', async function () {
      await expect(
        getStrategy({
          state: 'deposit',
          params: ZEROMAXCAP_STRATEGY_PARAMS,
          specificParams: [addresses.tokens.USDT, 0],
        }),
      ).to.be.revertedWith('BAB#041');
    });
  });

  describe('updateParams', function () {
    it('strategist can update duration, maxGasFeePercentage, maxAllocationPercentage, and maxTradeSlippagePercentage of a strategy', async function () {
      await strategyDataset.connect(signer1).updateParams([ONE_DAY_IN_SECONDS * 3, eth(0.1), eth(0.1), eth(), eth(10)]);

      expect(await strategyDataset.duration()).to.eq(ONE_DAY_IN_SECONDS * 3);
      expect(await strategyDataset.maxGasFeePercentage()).to.eq(eth(0.1));
      expect(await strategyDataset.maxTradeSlippagePercentage()).to.eq(eth(0.1));
      expect(await strategyDataset.maxAllocationPercentage()).to.eq(eth());
      expect(await strategyDataset.maxCapitalRequested()).to.eq(eth(10));
    });

    it('only strategist or gov can update params', async function () {
      await expect(
        strategyDataset.connect(signer3).updateParams([ONE_DAY_IN_SECONDS * 3, 0, 0, eth(), eth(10)]),
      ).to.be.revertedWith('BAB#032');
    });
  });

  describe('getStrategyDetails', async function () {
    it('should return the expected strategy properties', async function () {
      const [
        address,
        strategist,
        operationsCount,
        stake,
        totalPositiveVotes,
        totalNegativeVotes,
        capitalAllocated,
        capitalReturned,
        duration,
        expectedReturn,
        maxCapitalRequested,
        strategyNft,
        enteredAt,
      ] = await strategyDataset.getStrategyDetails();

      expect(address).to.equal(strategyDataset.address);
      expect(strategist).to.equal(signer1.address);
      expect(stake).to.equal(eth('0.1'));

      expect(totalPositiveVotes).to.equal(eth('0.1'));
      expect(totalNegativeVotes).to.equal(0);

      expect(operationsCount).to.equal(1);
      expect(capitalAllocated).to.equal(ethers.BigNumber.from(0));
      expect(capitalReturned).to.equal(ethers.BigNumber.from(0));
      expect(duration).to.equal(ethers.BigNumber.from(ONE_DAY_IN_SECONDS * 30));
      expect(expectedReturn).to.equal(eth('0.05'));
      expect(maxCapitalRequested).to.equal(eth('10'));
      expect(strategyNft).to.equal(await babController.strategyNFT());
      expect(enteredAt.isZero()).to.equal(false);
    });
  });

  describe('getStrategyState', async function () {
    it('should return the expected strategy state', async function () {
      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyDataset.getStrategyState();

      expect(address).to.equal(strategyDataset.address);
      expect(active).to.equal(false);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.equal(ethers.BigNumber.from(0));
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));
    });
  });

  describe('resolveVoting', async function () {
    it('should push results of the voting on-chain', async function () {
      const signer1Balance = await garden2.balanceOf(signer1.getAddress());
      const signer2Balance = await garden2.balanceOf(signer2.getAddress());

      await strategyCandidate
        .connect(keeper)
        .resolveVoting([signer1.getAddress(), signer2.getAddress()], [signer1Balance, signer2Balance], 42, {
          gasPrice: 0,
        });

      expect(await strategyCandidate.getUserVotes(signer1.getAddress())).to.equal(signer1Balance);
      expect(await strategyCandidate.getUserVotes(signer2.getAddress())).to.equal(signer2Balance);

      const [address, , , , totalPositveVotes, totalNegativeVotes] = await strategyCandidate.getStrategyDetails();

      // The stake is counted as votes of the strategists
      expect(totalPositveVotes).to.equal(eth().mul(5));
      expect(totalNegativeVotes).to.equal(0);

      const [, active, dataSet, finalized, executedAt, exitedAt] = await strategyCandidate.getStrategyState();

      expect(address).to.equal(strategyCandidate.address);
      expect(active).to.equal(true);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.equal(ethers.BigNumber.from(0));
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));
    });

    it("can't vote if voting window is closed", async function () {
      const signer1Balance = await garden2.balanceOf(signer1.getAddress());
      const signer2Balance = await garden2.balanceOf(signer2.getAddress());

      increaseTime(ONE_DAY_IN_SECONDS * 7);

      await expect(
        strategyCandidate
          .connect(keeper)
          .resolveVoting([signer1.getAddress(), signer2.getAddress()], [signer1Balance, signer2Balance], 42, {
            gasPrice: 0,
          }),
      ).to.be.revertedWith('BAB#043');
    });

    it("can't push voting results twice", async function () {
      const signer1Balance = await garden2.balanceOf(signer1.getAddress());
      const signer2Balance = await garden2.balanceOf(signer2.getAddress());

      await strategyCandidate
        .connect(keeper)
        .resolveVoting([signer1.getAddress(), signer2.getAddress()], [signer1Balance, signer2Balance], 42, {
          gasPrice: 0,
        });

      await expect(
        strategyCandidate
          .connect(keeper)
          .resolveVoting([signer1.getAddress(), signer2.getAddress()], [signer1Balance, signer2Balance], 42, {
            gasPrice: 0,
          }),
      ).to.be.revertedWith('BAB#042');
    });
  });

  describe('executeStrategy', async function () {
    it('should execute strategy', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      await executeStrategy(strategyContract, { amount: eth().mul(2), fee: 42 });

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyContract.getStrategyState();

      expect(address).to.equal(strategyContract.address);
      expect(active).to.equal(true);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.not.equal(0);
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));
    });

    it('should be able to add more capital in tranches to an active strategy', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      await executeStrategy(strategyContract, { amount: eth(), fee: 42 });
      await executeStrategy(strategyContract, { amount: eth(), fee: 42 });

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyContract.getStrategyState();

      expect(address).to.equal(strategyContract.address);
      expect(active).to.equal(true);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.not.equal(0);
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));

      expect(await strategyContract.capitalAllocated()).to.equal(eth().mul(2));
    });

    it('should not be able to unwind an active strategy with not enough capital', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'active',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );
      await expect(strategyContract.unwindStrategy(eth())).to.be.reverted;
    });

    it('should be able to unwind an active strategy with enough capital', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      await executeStrategy(strategyContract, { amount: eth().mul(2) });

      expect(await strategyContract.capitalAllocated()).to.equal(eth('2'));

      await strategyContract.connect(owner).unwindStrategy(eth(), await strategyContract.getNAV());

      expect(await strategyContract.capitalAllocated()).to.equal(eth());
      expect(await wethToken.balanceOf(garden1.address)).to.be.gt(eth());
    });

    it('should not be able to unwind an active strategy with enough capital if it is not the owner', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );
      expect(await wethToken.balanceOf(garden1.address)).to.be.gt(eth('2'));

      await executeStrategy(strategyContract, { amount: eth().mul(2) });

      await expect(strategyContract.connect(signer3).unwindStrategy(eth())).to.be.reverted;
    });
    it('should not be able to unwind an active strategy if strategy is over', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );
      await executeStrategy(strategyContract, { amount: eth().mul(2) });
      await increaseTime(ONE_DAY_IN_SECONDS * 30);

      await expect(
        strategyContract.connect(owner).unwindStrategy(eth(), await strategyContract.getNAV()),
      ).to.be.revertedWith('BAB#050');
    });

    it('can execute strategy twice', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'active',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      deposit(garden1, [signer1, signer2]);

      await executeStrategy(strategyContract);

      const [, , , , executedAt] = await strategyContract.getStrategyState();

      await executeStrategy(strategyContract);

      const [, , , , newExecutedAt] = await strategyContract.getStrategyState();

      // doesn't update executedAt
      expect(executedAt).to.be.equal(newExecutedAt);
    });

    it('refuse to pay a high fee to the keeper', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      increaseTime(ONE_DAY_IN_SECONDS * 2);

      await expect(
        strategyContract.connect(keeper).executeStrategy(eth(), eth().mul(100), {
          gasPrice: 0,
        }),
      ).to.be.revertedWith('BAB#019');
    });
  });

  describe('getNAV', async function () {
    it('should get the NAV value of a long strategy', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'active',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );
      const nav = await strategyContract.getNAV();
      expect(await strategyContract.capitalAllocated()).to.equal(eth());
      expect(nav).to.be.closeTo(eth().mul(1), eth().div(100));
    });

    it('should get the NAV value of a Yearn Farming strategy', async function () {
      const strategyContract = await createStrategy(
        'vault',
        'active',
        [signer1, signer2, signer3],
        yearnVaultIntegration.address,
        garden1,
      );
      const nav = await strategyContract.getNAV();
      expect(await strategyContract.capitalAllocated()).to.equal(eth());
      expect(nav).to.be.closeTo(eth().mul(1), eth().div(10));
    });

    it('should get the NAV value of a lend strategy', async function () {
      const strategyContract = await createStrategy(
        'lend',
        'active',
        [signer1, signer2, signer3],
        aaveLendIntegration.address,
        garden1,
      );
      const nav = await strategyContract.getNAV();
      expect(await strategyContract.capitalAllocated()).to.equal(eth());
      expect(nav).to.be.closeTo(eth().mul(1), eth().div(50));
    });

    it.skip('should get the NAV value of a BalancerPool strategy', async function () {
      const strategyContract = await createStrategy(
        'lp',
        'active',
        [signer1, signer2, signer3],
        balancerIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [addresses.balancer.pools.wethdai, 0],
      );

      const nav = await strategyContract.getNAV();
      expect(await strategyContract.capitalAllocated()).to.equal(eth());
      // So much slipage at Balancer 😭
      expect(nav).to.be.closeTo(eth().mul(1), eth().div(30));
    });

    it('should get the NAV value of a OneInchPool strategy', async function () {
      // const daiWethOneInchPair = await ethers.getContractAt('IMooniswap', addresses.oneinch.pools.wethdai);
      const strategyContract = await createStrategy(
        'lp',
        'active',
        [signer1, signer2, signer3],
        oneInchPoolIntegration.address,
        garden1,
        keeper,
        DEFAULT_STRATEGY_PARAMS,
        [addresses.oneinch.pools.wethdai, 0],
      );

      const nav = await strategyContract.getNAV();
      expect(await strategyContract.capitalAllocated()).to.equal(eth());
      expect(nav).to.be.closeTo(eth().mul(1), eth().div(20));
    });

    it('should get the NAV value of a UniswapPool strategy', async function () {
      const strategyContract = await createStrategy(
        'lp',
        'active',
        [signer1, signer2, signer3],
        uniswapPoolIntegration.address,
        garden1,
        keeper,
        DEFAULT_STRATEGY_PARAMS,
        [addresses.uniswap.pairs.wethdai, 0],
      );
      const nav = await strategyContract.getNAV();
      expect(await strategyContract.capitalAllocated()).to.equal(eth());
      expect(nav).to.be.closeTo(eth().mul(1), eth().div(100));
    });
  });

  describe('finalizeStrategy', async function () {
    it('should finalize strategy with negative profits', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      await executeStrategy(strategyContract, { fee: eth(0.1), amount: eth().mul(4) });

      // add extra WETH to repay keeper
      await garden1.connect(signer1).deposit(eth().mul(2), 1, signer1.address, false, {
        value: eth().mul(2),
      });

      await finalizeStrategy(strategyContract);
      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyContract.getStrategyState();

      expect(address).to.equal(strategyContract.address);
      expect(active).to.equal(false);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(true);
      expect(executedAt).to.not.equal(0);
      expect(exitedAt).to.not.equal(0);

      // Keeper gets paid
      expect(await wethToken.balanceOf(keeper.address)).to.be.closeTo(eth(0.1), eth());
      expect(await garden1.keeperDebt()).to.equal(0);

      const capitalAllocated = await strategyContract.capitalAllocated();
      const capitalReturned = await strategyContract.capitalReturned();

      expect(capitalReturned).to.be.lt(capitalAllocated);
      expect(await wethToken.balanceOf(garden1.address)).to.be.closeTo(eth(6.9), eth().div(10));
    });

    it('should finalize strategy with profits', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'active',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      await injectFakeProfits(strategyContract, eth('1000'));
      await finalizeStrategy(strategyContract);
      const capitalAllocated = await strategyContract.capitalAllocated();
      const capitalReturned = await strategyContract.capitalReturned();

      expect(capitalReturned).to.be.gt(capitalAllocated);
    });

    it("can't finalize strategy twice", async function () {
      const strategyContract = await createStrategy(
        'buy',
        'active',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      await finalizeStrategy(strategyContract);

      await expect(
        strategyContract.connect(keeper).finalizeStrategy(42, 'http://', 0, { gasPrice: 0 }),
      ).to.be.revertedWith('BAB#050');
    });
    it("can't finalize strategy if reserveAssetOut is below minReserveOut", async function () {
      const strategyContract = await createStrategy(
        'buy',
        'active',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      const minReserveOut = await strategyContract.capitalAllocated();

      await increaseTime(ONE_DAY_IN_SECONDS * 30);

      await expect(
        strategyContract.connect(keeper).finalizeStrategy(42, 'http://', minReserveOut, { gasPrice: 0 }),
      ).to.be.revertedWith('BAB#108');
    });
    it('can finalize strategy if reserveAssetOut is above minReserveOut', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'active',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      const minReserveOut = await strategyContract.capitalAllocated();

      await increaseTime(ONE_DAY_IN_SECONDS * 30);

      await expect(
        strategyContract.connect(keeper).finalizeStrategy(42, 'http://', minReserveOut.div(2), { gasPrice: 0 }),
      ).to.be.not.reverted;
    });
  });

  describe('sweep', async function () {
    it('can sweep with a custom slippage', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      await executeStrategy(strategyContract, { fee: eth(0.1), amount: eth().mul(4) });

      await garden1.connect(signer1).deposit(eth().mul(2), 1, signer1.address, false, {
        value: eth().mul(2),
      });

      await finalizeStrategy(strategyContract);

      await fund([strategyContract.address]);

      const balanceBefore = await weth.balanceOf(garden1.address);

      await strategyContract.sweep(addresses.tokens.DAI, eth(0.5));

      expect((await weth.balanceOf(garden1.address)).sub(balanceBefore)).to.gt(eth(100));
    });
  });

  describe('Profits and re-staking (compounding) calculations', async function () {
    it('should correctly calculate profits (strategist and stewards) and re-staking values of 5 strategies', async function () {
      const [long1, long2, long3, long4, long5] = await createStrategies([
        { garden: garden1 },
        { garden: garden1 },
        { garden: garden2 },
        { garden: garden2 },
        { garden: garden2 },
      ]);

      await executeStrategy(long1, eth());
      await executeStrategy(long2, eth());
      await executeStrategy(long3, eth());
      await executeStrategy(long4, eth());
      await executeStrategy(long5, eth());

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      await injectFakeProfits(long1, eth().mul(200));
      await finalizeStrategy(long1);

      // Add calculations long1
      const returnedLong1 = await long1.capitalReturned();
      const allocatedLong1 = await long1.capitalAllocated();
      const profitLong1 = returnedLong1.sub(allocatedLong1);
      const calculatedSetAsideLong1 = profitLong1.mul(15).div(100);

      const reserveAssetRewardsSetAsideLong1 = await garden1.reserveAssetRewardsSetAside();
      expect(reserveAssetRewardsSetAsideLong1).to.be.closeTo(
        calculatedSetAsideLong1,
        reserveAssetRewardsSetAsideLong1.div(100),
      );

      // Strategy long2 has not profits
      await finalizeStrategy(long2);
      const reserveAssetRewardsSetAsideLong2 = await garden1.reserveAssetRewardsSetAside();
      expect(reserveAssetRewardsSetAsideLong2).to.be.equal(reserveAssetRewardsSetAsideLong1);

      await injectFakeProfits(long3, eth().mul(200));
      await finalizeStrategy(long3);
      // Add calculations long3
      const returnedLong3 = await long3.capitalReturned();
      const allocatedLong3 = await long3.capitalAllocated();
      const profitLong3 = returnedLong3.sub(allocatedLong3);
      const calculatedSetAsideLong3 = profitLong3.mul(15).div(100);

      const reserveAssetRewardsSetAsideLong3 = await garden2.reserveAssetRewardsSetAside();
      expect(reserveAssetRewardsSetAsideLong3).to.be.closeTo(
        calculatedSetAsideLong3,
        reserveAssetRewardsSetAsideLong3.div(100),
      );

      await injectFakeProfits(long4, eth().mul(222));
      await finalizeStrategy(long4);
      // Add calculations long4
      const returnedLong4 = await long4.capitalReturned();
      const allocatedLong4 = await long4.capitalAllocated();
      const profitLong4 = returnedLong4.sub(allocatedLong4);
      const calculatedSetAsideLong4 = profitLong4.mul(15).div(100);

      const reserveAssetRewardsSetAsideLong4 = await garden2.reserveAssetRewardsSetAside();
      expect(reserveAssetRewardsSetAsideLong4).to.be.closeTo(
        calculatedSetAsideLong4.add(calculatedSetAsideLong3),
        reserveAssetRewardsSetAsideLong4.div(100),
      );

      await injectFakeProfits(long5, eth().mul(222));
      await finalizeStrategy(long5);
      // Add calculations long5
      const returnedLong5 = await long5.capitalReturned();
      const allocatedLong5 = await long5.capitalAllocated();
      const profitLong5 = returnedLong5.sub(allocatedLong5);
      const calculatedSetAsideLong5 = profitLong5.mul(15).div(100);

      const reserveAssetRewardsSetAsideLong5 = await garden2.reserveAssetRewardsSetAside();
      expect(reserveAssetRewardsSetAsideLong5).to.be.closeTo(
        calculatedSetAsideLong5.add(calculatedSetAsideLong4.add(calculatedSetAsideLong3)),
        reserveAssetRewardsSetAsideLong5.div(100),
      );
    });

    it('should correctly receive the performance fee (in WETH) by the treasury in profit strategies', async function () {
      const [long1, long2, long3, long4, long5] = await createStrategies([
        { garden: garden1 },
        { garden: garden1 },
        { garden: garden2 },
        { garden: garden2 },
        { garden: garden2 },
      ]);

      await executeStrategy(long1, eth());
      await executeStrategy(long2, eth());
      await executeStrategy(long3, eth());
      await executeStrategy(long4, eth());
      await executeStrategy(long5, eth());

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      const treasuryBalance0 = await wethToken.balanceOf(heart.address);
      expect(treasuryBalance0.toString()).to.be.equal('25000000000000000');

      await injectFakeProfits(long1, eth(200));
      await finalizeStrategy(long1);

      const treasuryBalance1 = await wethToken.balanceOf(heart.address);
      expect(treasuryBalance1).to.be.closeTo(from('27488436671748554'), treasuryBalance1.div(20));

      await finalizeStrategy(long2);
      const treasuryBalance2 = await wethToken.balanceOf(heart.address);
      expect(treasuryBalance2).to.be.closeTo(from('27488436671748554'), treasuryBalance2.div(20));

      await injectFakeProfits(long3, eth(200));
      await finalizeStrategy(long3);
      const treasuryBalance3 = await wethToken.balanceOf(heart.address);
      expect(treasuryBalance3).to.be.closeTo(from('30828176461267569'), treasuryBalance3.div(20));

      await injectFakeProfits(long4, eth(200));
      await finalizeStrategy(long4);
      const treasuryBalance4 = await wethToken.balanceOf(heart.address);
      expect(treasuryBalance4).to.be.closeTo(from('33737903640157303'), treasuryBalance4.div(20));

      await injectFakeProfits(long5, eth(222));
      await finalizeStrategy(long5);
      const treasuryBalance5 = await wethToken.balanceOf(heart.address);
      expect(treasuryBalance5).to.be.closeTo(from('36998685764437278'), treasuryBalance5.div(20));
    });

    it('capital returned should equals profits; param 1 + param 2 + protocol performance fee 5%', async function () {
      const [long1] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long1, eth());

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      const treasuryBalance0 = await wethToken.balanceOf(heart.address);

      await injectFakeProfits(long1, eth().mul(200));

      await finalizeStrategy(long1);

      const treasuryBalance1 = await wethToken.balanceOf(heart.address);
      const feeLong1 = treasuryBalance1 - treasuryBalance0;
      const reserveAssetRewardsSetAsideLong1 = await garden1.reserveAssetRewardsSetAside();
      const capitalReturnedLong1 = await long1.capitalReturned();
      const valueLong1 = reserveAssetRewardsSetAsideLong1.add(feeLong1);

      // TODO: Calculate and test reserveAssetRewardsSetAside, heart fee, profits
      // expect(capitalReturnedLong1).to.be.closeTo(valueLong1, 10);
    });
  });
});
