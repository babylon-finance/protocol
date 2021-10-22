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
  DEFAULT_STRATEGY_PARAMS,
} = require('fixtures/StrategyHelper.js');
const { increaseTime, normalizeDecimals, getERC20, getContract, parse, from, eth } = require('utils/test-helpers');

const addresses = require('lib/addresses');
const { ONE_DAY_IN_SECONDS, ONE_ETH } = require('lib/constants.js');
const { setupTests } = require('fixtures/GardenFixture');
const { getStrategy } = require('fixtures/StrategyHelper');
const ZEROMAXCAP_STRATEGY_PARAMS = [
  eth(0), // _maxCapitalRequested == 0
  eth(0.1), // _stake
  ONE_DAY_IN_SECONDS * 30, // _strategyDuration
  eth(0.05), // 5% _expectedReturn,
  eth(0.1), // 10% _maxAllocationPercentage,
  eth(0.05), // 5% _maxGasFeePercentage
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
  let aaveLendIntegration;
  let uniswapV3TradeIntegration;
  let uniswapPoolIntegration;
  let balancerIntegration;
  let oneInchPoolIntegration;
  let yearnVaultIntegration;
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

  beforeEach(async () => {
    ({
      owner,
      keeper,
      babController,
      signer1,
      garden1,
      garden2,
      treasury,
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
    } = await setupTests()());

    strategyDataset = await ethers.getContractAt('Strategy', strategy11);
    strategyCandidate = await ethers.getContractAt('Strategy', strategy21);

    wethToken = await getERC20(addresses.tokens.WETH);
  });

  describe('Strategy Deployment', async function () {
    it('should NOT initialize a strategy with maxcapitalrequested of 0', async function () {
      await expect(
        getStrategy({
          state: 'deposit',
          params: ZEROMAXCAP_STRATEGY_PARAMS,
          specificParams: [addresses.tokens.USDT, 0],
        }),
      ).to.be.revertedWith('BAB#093');
    });
  });

  describe('changeStrategyDuration', function () {
    it('strategist should be able to change the duration of an strategy strategy', async function () {
      await expect(strategyDataset.connect(signer1).changeStrategyDuration(ONE_DAY_IN_SECONDS * 3)).to.not.be.reverted;
    });

    it('other member should NOT be able to change the duration of an strategy', async function () {
      await expect(strategyDataset.connect(signer3).changeStrategyDuration(ONE_DAY_IN_SECONDS * 3)).to.be.revertedWith(
        'BAB#032',
      );
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
      expect(stake).to.equal(ethers.utils.parseEther('0.1'));

      expect(totalPositiveVotes).to.equal(ethers.utils.parseEther('0.1'));
      expect(totalNegativeVotes).to.equal(0);

      expect(operationsCount).to.equal(1);
      expect(capitalAllocated).to.equal(ethers.BigNumber.from(0));
      expect(capitalReturned).to.equal(ethers.BigNumber.from(0));
      expect(duration).to.equal(ethers.BigNumber.from(ONE_DAY_IN_SECONDS * 30));
      expect(expectedReturn).to.equal(ethers.utils.parseEther('0.05'));
      expect(maxCapitalRequested).to.equal(ethers.utils.parseEther('10'));
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
      expect(totalPositveVotes).to.equal(ONE_ETH.mul(5));
      expect(totalNegativeVotes).to.equal(0);

      const [, active, dataSet, finalized, executedAt, exitedAt] = await strategyCandidate.getStrategyState();

      expect(address).to.equal(strategyCandidate.address);
      expect(active).to.equal(true);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.equal(ethers.BigNumber.from(0));
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));

      // Keeper gets paid
      expect(await wethToken.balanceOf(await keeper.getAddress())).to.equal(42);
      expect(await garden2.keeperDebt()).to.equal(0);
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

      await executeStrategy(strategyContract, { amount: ONE_ETH.mul(2), fee: 42 });

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyContract.getStrategyState();

      expect(address).to.equal(strategyContract.address);
      expect(active).to.equal(true);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.not.equal(0);
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));

      // Keeper gets paid
      expect(await wethToken.balanceOf(await keeper.getAddress())).to.equal(42);
      expect(await garden1.keeperDebt()).to.equal(0);
    });

    it('should be able to add more capital in tranches to an active strategy', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      await executeStrategy(strategyContract, { amount: ONE_ETH, fee: 42 });
      await executeStrategy(strategyContract, { amount: ONE_ETH, fee: 42 });

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyContract.getStrategyState();

      expect(address).to.equal(strategyContract.address);
      expect(active).to.equal(true);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.not.equal(0);
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));

      // Keeper gets paid
      expect(await wethToken.balanceOf(await keeper.getAddress())).to.equal(84);
      expect(await garden1.keeperDebt()).to.equal(0);
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH.mul(2));
    });

    it('should not be able to unwind an active strategy with not enough capital', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'active',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );
      await expect(strategyContract.unwindStrategy(ethers.utils.parseEther('1'))).to.be.reverted;
    });

    it('should be able to unwind an active strategy with enough capital', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      await executeStrategy(strategyContract, { amount: ONE_ETH.mul(2) });

      expect(await strategyContract.capitalAllocated()).to.equal(ethers.utils.parseEther('2'));

      await strategyContract.connect(owner).unwindStrategy(ONE_ETH, await strategyContract.getNAV());

      expect(await strategyContract.capitalAllocated()).to.equal(ethers.utils.parseEther('1'));
      expect(await wethToken.balanceOf(garden1.address)).to.be.gt(ethers.utils.parseEther('1'));
    });

    it('should not be able to unwind an active strategy with enough capital if it is not the owner', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );
      expect(await wethToken.balanceOf(garden1.address)).to.be.gt(ethers.utils.parseEther('2'));

      await executeStrategy(strategyContract, { amount: ONE_ETH.mul(2) });

      await expect(strategyContract.connect(signer3).unwindStrategy(ethers.utils.parseEther('1'))).to.be.reverted;
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
        strategyContract.connect(keeper).executeStrategy(ONE_ETH, ONE_ETH.mul(100), {
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
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
      expect(nav).to.be.closeTo(ONE_ETH.mul(1), ONE_ETH.div(100));
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
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
      expect(nav).to.be.closeTo(ONE_ETH.mul(1), ONE_ETH.div(10));
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
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
      expect(nav).to.be.closeTo(ONE_ETH.mul(1), ONE_ETH.div(50));
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
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
      // So much slipage at Balancer 😭
      expect(nav).to.be.closeTo(ONE_ETH.mul(1), ONE_ETH.div(30));
    });

    it('should get the NAV value of a OneInchPool strategy', async function () {
      // const daiWethOneInchPair = await ethers.getContractAt('IMooniswap', addresses.oneinch.pools.wethdai);
      const strategyContract = await createStrategy(
        'lp',
        'active',
        [signer1, signer2, signer3],
        oneInchPoolIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [addresses.oneinch.pools.wethdai, 0],
      );

      const nav = await strategyContract.getNAV();
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
      expect(nav).to.be.closeTo(ONE_ETH.mul(1), ONE_ETH.div(20));
    });

    it('should get the NAV value of a UniswapPool strategy', async function () {
      const strategyContract = await createStrategy(
        'lp',
        'active',
        [signer1, signer2, signer3],
        uniswapPoolIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [addresses.uniswap.pairs.wethdai, 0],
      );
      const nav = await strategyContract.getNAV();
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
      expect(nav).to.be.closeTo(ONE_ETH.mul(1), ONE_ETH.div(100));
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

      await executeStrategy(strategyContract, { fee: ONE_ETH, amount: ONE_ETH.mul(4) });

      // add extra WETH to repay keeper
      await garden1.connect(signer1).deposit(ONE_ETH.mul(2), 1, signer1.address, false, {
        value: ONE_ETH.mul(2),
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
      expect(await wethToken.balanceOf(keeper.address)).to.be.closeTo(ONE_ETH, ONE_ETH);
      expect(await garden1.keeperDebt()).to.equal(0);

      const capitalAllocated = await strategyContract.capitalAllocated();
      const capitalReturned = await strategyContract.capitalReturned();

      expect(capitalReturned).to.be.lt(capitalAllocated);
      // takes into account ETH send to withdrawal window
      expect(await wethToken.balanceOf(garden1.address)).to.be.closeTo(ONE_ETH.mul(6), ONE_ETH.div(10));
    });

    it('should finalize strategy with profits', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'active',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      await injectFakeProfits(strategyContract, ethers.utils.parseEther('1000'));
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

      await expect(strategyContract.finalizeStrategy(42, 'http://', { gasPrice: 0 })).to.be.reverted;
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

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH);
      await executeStrategy(long3, ONE_ETH);
      await executeStrategy(long4, ONE_ETH);
      await executeStrategy(long5, ONE_ETH);

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      await injectFakeProfits(long1, ONE_ETH.mul(200));
      await finalizeStrategy(long1);

      const reserveAssetRewardsSetAsideLong1 = await garden1.reserveAssetRewardsSetAside();
      expect(reserveAssetRewardsSetAsideLong1).to.be.closeTo(
        '7465310015245664',
        reserveAssetRewardsSetAsideLong1.div(100),
      );

      // Strategy long2 has not profits
      await finalizeStrategy(long2);

      const reserveAssetRewardsSetAsideLong2 = await garden1.reserveAssetRewardsSetAside();
      expect(reserveAssetRewardsSetAsideLong2).to.be.equal(reserveAssetRewardsSetAsideLong1);

      await injectFakeProfits(long3, ONE_ETH.mul(200));
      await finalizeStrategy(long3);

      const reserveAssetRewardsSetAsideLong3 = await garden2.reserveAssetRewardsSetAside();
      expect(reserveAssetRewardsSetAsideLong3).to.be.closeTo(
        '7457155378612255',
        reserveAssetRewardsSetAsideLong3.div(100),
      );

      await injectFakeProfits(long4, ONE_ETH.mul(222));
      await finalizeStrategy(long4);

      const reserveAssetRewardsSetAsideLong4 = await garden2.reserveAssetRewardsSetAside();
      expect(reserveAssetRewardsSetAsideLong4).to.be.closeTo(
        '15746963198401948',
        reserveAssetRewardsSetAsideLong4.div(100),
      );

      await injectFakeProfits(long5, ONE_ETH.mul(222));
      await finalizeStrategy(long5);

      const reserveAssetRewardsSetAsideLong5 = await garden2.reserveAssetRewardsSetAside();
      expect(reserveAssetRewardsSetAsideLong5).to.be.closeTo(
        '24032618688505816',
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

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH);
      await executeStrategy(long3, ONE_ETH);
      await executeStrategy(long4, ONE_ETH);
      await executeStrategy(long5, ONE_ETH);

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      const treasuryBalance0 = await wethToken.balanceOf(treasury.address);
      expect(treasuryBalance0.toString()).to.be.equal('25000000000000000');

      await injectFakeProfits(long1, ONE_ETH.mul(200));
      await finalizeStrategy(long1);

      const treasuryBalance1 = await wethToken.balanceOf(treasury.address);
      expect(treasuryBalance1).to.be.closeTo(ethers.BigNumber.from('27488436671748554'), treasuryBalance1.div(20));

      // Strategy long2 has not profits
      await finalizeStrategy(long2);
      const treasuryBalance2 = await wethToken.balanceOf(treasury.address);
      expect(treasuryBalance2).to.be.closeTo(ethers.BigNumber.from('27488436671748554'), treasuryBalance2.div(20));

      await injectFakeProfits(long3, ONE_ETH.mul(200));
      await finalizeStrategy(long3);
      const treasuryBalance3 = await wethToken.balanceOf(treasury.address);
      expect(treasuryBalance3).to.be.closeTo(ethers.BigNumber.from('29974155131285971'), treasuryBalance3.div(20));

      await injectFakeProfits(long4, ONE_ETH.mul(222));
      await finalizeStrategy(long4);
      const treasuryBalance4 = await wethToken.balanceOf(treasury.address);
      expect(treasuryBalance4).to.be.closeTo(ethers.BigNumber.from('32737424404549201'), treasuryBalance4.div(20));

      await injectFakeProfits(long5, ONE_ETH.mul(222));
      await finalizeStrategy(long5);
      const treasuryBalance5 = await wethToken.balanceOf(treasury.address);
      expect(treasuryBalance5).to.be.closeTo(ethers.BigNumber.from('35499309567917156'), treasuryBalance5.div(20));
    });

    it('capital returned should equals profits; param 1 + param 2 + protocol performance fee 5%', async function () {
      const [long1] = await createStrategies([{ garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);

      increaseTime(ONE_DAY_IN_SECONDS * 30);

      const treasuryBalance0 = await wethToken.balanceOf(treasury.address);

      await injectFakeProfits(long1, ONE_ETH.mul(200));

      await finalizeStrategy(long1);
      const treasuryBalance1 = await wethToken.balanceOf(treasury.address);
      const feeLong1 = treasuryBalance1 - treasuryBalance0;
      const reserveAssetRewardsSetAsideLong1 = await garden1.reserveAssetRewardsSetAside();
      const capitalReturnedLong1 = await long1.capitalReturned();
      const valueLong1 = reserveAssetRewardsSetAsideLong1.add(feeLong1);

      // TODO: Calculate and test reserveAssetRewardsSetAside, treasury fee, profits
      // expect(capitalReturnedLong1).to.be.closeTo(valueLong1, 10);
    });
  });
});
