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
} = require('../fixtures/StrategyHelper.js');
const { createGarden } = require('../fixtures/GardenHelper');
const { increaseTime } = require('../utils/test-helpers');
const { MAX_UINT_256 } = require('../../lib/constants');

const addresses = require('../../lib/addresses');
const { ONE_DAY_IN_SECONDS, ONE_ETH, ADDRESS_ZERO } = require('../../lib/constants.js');
const { setupTests } = require('../fixtures/GardenFixture');
const { impersonateAddress } = require('../../lib/rpc');

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
  let aaveBorrowIntegration;
  let DAI;
  let WETH;
  let sushiswapPoolIntegration;
  let harvestVaultIntegration;
  let compoundBorrowIntegration;
  let compoundLendIntegration;

  // Deploys aave oracle with changed ETH price and inject its code into real aave oracle contract
  // code is available in AaveOracle.sol
  // constructor args are dai, dai source, fallback oracle, weth, took from etherscan
  async function changeETHPriceInAaveOracle(WETH) {
    const oracles = await ethers.getContractFactory('AaveOracleMock');
    const oracle = await oracles.deploy(
      ['0x6B175474E89094C44Da98b954EedeAC495271d0F'],
      ['0x773616E4d11A78F511299002da57A0a94577F1f4'],
      '0x5B09E578cfEAa23F1b11127A658855434e4F3e09',
      WETH.address,
    );
    const code = await hre.network.provider.send('eth_getCode', [oracle.address]);
    await hre.network.provider.send('hardhat_setCode', ['0xA50ba011c48153De246E5192C8f9258A2ba79Ca9', code]);
  }

  // Health factor see aave docs
  async function getHealthFactor(lendingPool, borrower) {
    const data = await lendingPool.getUserAccountData(borrower);
    return data.healthFactor;
  }

  // useless when amount < 1
  function normalizeToken(amount) {
    return amount.div(ethers.utils.parseEther('0.001')).toNumber() / 1000;
  }

  async function createStrategies(strategies) {
    const retVal = [];
    for (let i = 0; i < strategies.length; i++) {
      const strategy = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
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
      aaveBorrowIntegration,
      sushiswapPoolIntegration,
      harvestVaultIntegration,
      compoundBorrowIntegration,
      compoundLendIntegration,
    } = await setupTests()());

    strategyDataset = await ethers.getContractAt('Strategy', strategy11);
    strategyCandidate = await ethers.getContractAt('Strategy', strategy21);

    wethToken = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
    DAI = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
    WETH = await ethers.getContractAt('IERC20', addresses.tokens.WETH);

    daiWethPair = await ethers.getContractAt('IUniswapV2PairB', addresses.sushiswap.pairs.wethdai);
    ethSushiPair = await ethers.getContractAt('IUniswapV2PairB', addresses.sushiswap.pairs.ethsushi);
    ethSushiVault = await ethers.getContractAt('IHarvestVault', addresses.harvest.vaults.fETHSUSHI);
  });

  describe('Strategy Deployment', async function () {
    it('should deploy contract successfully', async function () {
      const deployed = await strategyDataset.deployed();
      expect(!!deployed).to.equal(true);
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
      ).to.be.revertedWith(/BAB#043/i);
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
      ).to.be.revertedWith(/BAB#042/i);
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

      await strategyContract.connect(owner).unwindStrategy(ONE_ETH);

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
      ).to.be.revertedWith(/BAB#019/i);
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
      expect(nav).to.be.closeTo(ONE_ETH.mul(1), ONE_ETH.div(100));
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

    it('should get the NAV value of a BalancerPool strategy', async function () {
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
      expect(nav).to.be.closeTo(ONE_ETH.mul(1), ONE_ETH.div(100));
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
      // Mining program has to be enabled before the strategy is created
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
      await finalizeStrategy(long1);

      const reserveAssetRewardsSetAsideLong1 = await garden1.reserveAssetRewardsSetAside();
      expect(reserveAssetRewardsSetAsideLong1).to.be.closeTo(
        '14600157511291044',
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
        '14544610528254611',
        reserveAssetRewardsSetAsideLong3.div(100),
      );

      await injectFakeProfits(long4, ONE_ETH.mul(222));
      await finalizeStrategy(long4);

      const reserveAssetRewardsSetAsideLong4 = await garden2.reserveAssetRewardsSetAside();
      expect(reserveAssetRewardsSetAsideLong4).to.be.closeTo(
        '30759450342788913',
        reserveAssetRewardsSetAsideLong4.div(100),
      );

      await injectFakeProfits(long5, ONE_ETH.mul(222));
      await finalizeStrategy(long5);

      const reserveAssetRewardsSetAsideLong5 = await garden2.reserveAssetRewardsSetAside();
      expect(reserveAssetRewardsSetAsideLong5).to.be.closeTo(
        '46945477482079494',
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
      expect(treasuryBalance1).to.be.closeTo(ethers.BigNumber.from('29866719170430347'), treasuryBalance1.div(100));

      // Strategy long2 has not profits
      await finalizeStrategy(long2);
      const treasuryBalance2 = await wethToken.balanceOf(treasury.address);
      expect(treasuryBalance2).to.be.closeTo(ethers.BigNumber.from('29866719170430347'), treasuryBalance2.div(100));

      await injectFakeProfits(long3, ONE_ETH.mul(200));
      await finalizeStrategy(long3);
      const treasuryBalance3 = await wethToken.balanceOf(treasury.address);
      expect(treasuryBalance3).to.be.closeTo(ethers.BigNumber.from('34714922679848550'), treasuryBalance3.div(100));

      await injectFakeProfits(long4, ONE_ETH.mul(222));
      await finalizeStrategy(long4);
      const treasuryBalance4 = await wethToken.balanceOf(treasury.address);
      expect(treasuryBalance4).to.be.closeTo(ethers.BigNumber.from('40119869284693317'), treasuryBalance4.div(100));

      await injectFakeProfits(long5, ONE_ETH.mul(222));
      await finalizeStrategy(long5);
      const treasuryBalance5 = await wethToken.balanceOf(treasury.address);
      expect(treasuryBalance5).to.be.closeTo(ethers.BigNumber.from('45515211664456843'), treasuryBalance5.div(100));
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

  describe('Security audit hacks -> checking fixes', function () {
    it(`should fail if trying to exploit updateMaxCollateralFactor and sweep with stucked funds`, async function () {
      const token = WETH.address;
      const asset1 = WETH;
      const asset2 = DAI;
      userBalanceBefore = await ethers.provider.getBalance(signer1.address);

      // signer1 creates with 1 ETH contribution
      const garden = await createGarden({ reserveAsset: token, signer: signer1 });
      // Create strategy with lend and borrow operations for exploit simplicity
      const strategyContract = await createStrategy(
        'borrow',
        'dataset',
        [signer1],
        [aaveLendIntegration.address, aaveBorrowIntegration.address],
        garden,
        false,
        [asset1.address, 0, asset2.address, 0],
      );
      const deposited = userBalanceBefore.sub(await ethers.provider.getBalance(signer1.address));
      const userGardenTokens = await garden.balanceOf(signer1.address);
      await strategyContract.connect(keeper).resolveVoting([signer1.address], [userGardenTokens], 0, { gasPrice: 0 });

      const lendingPool = await ethers.getContractAt('ILendingPool', '0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9');
      // Set maxCollateralFactor to 80% before strategy execution, max available for WETH collateral 80%, liquidate rate is 82.5%
      // The following call reverts "Transaction reverted: function call to a non-contract account" as we added the modifier isSystemContract
      //await aaveBorrowIntegration.connect(signer2).updateMaxCollateralFactor(ethers.utils.parseEther('0.8'));

      // Now that we avoid anyone calling, only a system contract can call it, we try the hack calling it from the strategy contract to check sweep fix
      const strategyAddress = await impersonateAddress(strategyContract.address);

      await aaveBorrowIntegration
        .connect(strategyAddress)
        .updateMaxCollateralFactor(ethers.utils.parseEther('0.8'), { gasPrice: 0 });

      const amount = ethers.utils.parseEther('0.994');
      await executeStrategy(strategyContract, { amount });

      // health factor is around 1.03
      // await getHealthFactor(lendingPool, strategyContract.address));
      // modify ETH price
      // for simplicity we changed WETH price
      await changeETHPriceInAaveOracle(WETH);
      // here is 0.99
      //await getHealthFactor(lendingPool, strategyContract.address));

      // Send tokens to signer2 for liquidation
      whaleSigner = await impersonateAddress('0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643');
      await DAI.connect(whaleSigner).transfer(signer2.address, ethers.utils.parseEther('100000'), {
        gasPrice: 0,
      });

      // Liquidate CDP with health factor < 1
      await DAI.connect(signer2).approve(lendingPool.address, MAX_UINT_256, { gasPrice: 0 });
      const attackerMaxBalance = normalizeToken(await DAI.balanceOf(signer2.address));

      await lendingPool
        .connect(signer2)
        .liquidationCall(WETH.address, DAI.address, strategyContract.address, MAX_UINT_256, false, { gasPrice: 0 });
      // await strategyContract.connect(signer3).sweep(DAI.address, {gasPrice: 0});
      // finalize strategy

      const attackerNewBalance = normalizeToken(await DAI.balanceOf(signer2.address));
      const attackUsedBalance = attackerMaxBalance - attackerNewBalance;

      await finalizeStrategy(strategyContract);

      await garden
        .connect(signer1)
        .withdraw(await garden.balanceOf(signer1.address), 1, signer1.address, false, strategyContract.address, {
          gasPrice: 0,
        });
      const userBalanceAfter = await ethers.provider.getBalance(signer1.address);
      // some losses (0.16) due to gas included
      if (userBalanceAfter.lt(userBalanceBefore)) {
        const loss = userBalanceBefore.sub(userBalanceAfter);
      } else {
        const profit = userBalanceAfter.sub(userBalanceBefore);
      }
      // ONLY_CONTRIBUTOR force to be contributor, so we deposit into the garden
      await garden.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
        gasPrice: 0,
      });
      await strategyContract.connect(signer1).sweep(DAI.address);
      const userBalanceAfterSweep = await ethers.provider.getBalance(signer1.address);
      await garden
        .connect(signer1)
        .withdraw(await garden.balanceOf(signer1.address), 1, signer1.address, false, strategyContract.address, {
          gasPrice: 0,
        });
      const userBalanceAfterSweepAndWithdraw = await ethers.provider.getBalance(signer1.address);

      if (userBalanceAfterSweepAndWithdraw.lt(userBalanceBefore)) {
        const loss = userBalanceBefore.sub(userBalanceAfterSweepAndWithdraw);
      } else {
        const profit = userBalanceAfterSweepAndWithdraw.sub(userBalanceBefore);
      }
      // We check that we now get funds back after recovering them from the strategy with 2% accuracy
      expect(userBalanceAfterSweepAndWithdraw).to.be.closeTo(userBalanceBefore, userBalanceBefore.div(50));
    });
    it('trying to block funds in a strategy using harvest', async function () {
      console.log('Trying create strategy');
      const strategyContract = await createStrategy(
        'lpStack',
        'vote',
        [signer1, signer2, signer3],
        [sushiswapPoolIntegration.address, harvestVaultIntegration.address],
        garden1,
        false,
        [ethSushiPair.address, 0, ethSushiVault.address, 0],
      );
      console.log('Strategy created');
      await executeStrategy(strategyContract);
      console.log('Strategy executed');
      expect(await ethSushiVault.balanceOf(strategyContract.address)).to.be.gt(0);

      console.log('Finalization always reverts because depositVaultOperation tries swap lp tokens to garden tokens');
      //await strategyContract.connect(signer1).sweep(ethSushiPair.address);
      await finalizeStrategy(strategyContract, 0);
      console.log('Strategy finalized');
      expect(await ethSushiPair.balanceOf(strategyContract.address)).to.equal(0);
    });
    it.only(`trying to block a strategy having more balance than debt for repay`, async function () {
      const token = WETH.address;
      userBalanceBefore = await ethers.provider.getBalance(signer1.address);
      // signer1 creates with 1 ETH contribution
      const garden = await createGarden({ reserveAsset: token, signer: signer1 });
      // Create strategy with lend and borrow operations for exploit simplicity
      const strategyContract = await createStrategy(
        'borrow',
        'dataset',
        [signer1],
        [compoundLendIntegration.address, compoundBorrowIntegration.address],
        garden,
        false,
        [ADDRESS_ZERO, 0, DAI.address, 0],
      );
      const userGardenTokens = await garden.balanceOf(signer1.address);
      await strategyContract.connect(keeper).resolveVoting([signer1.address], [userGardenTokens], 0, { gasPrice: 0 });

      const amount = ethers.utils.parseEther('0.9');
      await executeStrategy(strategyContract, { amount });
      // Send extra borrowed tokens to strategy
      whaleSigner = await impersonateAddress('0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643');
      await DAI.connect(whaleSigner).transfer(strategyContract.address, ethers.utils.parseEther('1'), {
        gasPrice: 0,
      });
      // not to be reverted
      await finalizeStrategy(strategyContract);
    });
  });
});
