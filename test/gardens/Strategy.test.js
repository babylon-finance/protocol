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
const { increaseTime } = require('../utils/test-helpers');

const addresses = require('../../lib/addresses');
const { ONE_DAY_IN_SECONDS, ONE_ETH } = require('../../lib/constants.js');
const { setupTests } = require('../fixtures/GardenFixture');

describe('Strategy', function () {
  let strategyDataset;
  let strategyCandidate;
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
  let daiToken;
  let daiWethPair;
  let aaveLendIntegration;
  let kyberTradeIntegration;
  let uniswapPoolIntegration;
  let balancerIntegration;
  let oneInchPoolIntegration;
  let yearnVaultIntegration;

  beforeEach(async () => {
    ({
      owner,
      keeper,
      signer1,
      garden1,
      garden2,
      strategy11,
      strategy21,
      signer2,
      signer3,
      aaveLendIntegration,
      kyberTradeIntegration,
      uniswapPoolIntegration,
      balancerIntegration,
      oneInchPoolIntegration,
      yearnVaultIntegration,
    } = await setupTests()());

    strategyDataset = await ethers.getContractAt('Strategy', strategy11);
    strategyCandidate = await ethers.getContractAt('Strategy', strategy21);

    wethToken = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
    daiToken = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
    daiWethPair = await ethers.getContractAt('IUniswapV2PairB', addresses.uniswap.pairs.wethdai);
  });

  describe('Strategy Deployment', async function () {
    it('should deploy contract successfully', async function () {
      const deployed = await strategyDataset.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe('changeStrategyDuration', function () {
    it('strategist should be able to change the duration of an strategy strategy', async function () {
      await expect(strategyDataset.connect(signer1).changeStrategyDuration(ONE_DAY_IN_SECONDS)).to.not.be.reverted;
    });

    it('other member should be able to change the duration of an strategy', async function () {
      await expect(strategyDataset.connect(signer3).changeStrategyDuration(ONE_DAY_IN_SECONDS)).to.be.reverted;
    });
  });

  describe('getStrategyDetails', async function () {
    it('should return the expected strategy properties', async function () {
      const [
        address,
        strategist,
        operationsCount,
        stake,
        absoluteTotalVotes,
        totalVotes,
        capitalAllocated,
        capitalReturned,
        duration,
        expectedReturn,
        maxCapitalRequested,
        minRebalanceCapital,
        enteredAt,
      ] = await strategyDataset.getStrategyDetails();

      expect(address).to.equal(strategyDataset.address);
      expect(strategist).to.equal(signer1.address);
      expect(stake).to.equal(ethers.utils.parseEther('0.1'));
      expect(absoluteTotalVotes).to.equal(ethers.utils.parseEther('0.1'));
      expect(totalVotes).to.equal(ethers.utils.parseEther('0.1'));
      expect(operationsCount).to.equal(1);
      expect(capitalAllocated).to.equal(ethers.BigNumber.from(0));
      expect(capitalReturned).to.equal(ethers.BigNumber.from(0));
      expect(duration).to.equal(ethers.BigNumber.from(ONE_DAY_IN_SECONDS * 30));
      expect(expectedReturn).to.equal(ethers.utils.parseEther('0.05'));
      expect(maxCapitalRequested).to.equal(ethers.utils.parseEther('10'));
      expect(minRebalanceCapital).to.equal(ethers.utils.parseEther('1'));
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
        .resolveVoting(
          [signer1.getAddress(), signer2.getAddress()],
          [signer1Balance, signer2Balance],
          signer1Balance.add(signer2Balance).toString(),
          signer1Balance.add(signer2Balance).toString(),
          42,
          {
            gasPrice: 0,
          },
        );

      expect(await strategyCandidate.getUserVotes(signer1.getAddress())).to.equal(signer1Balance);
      expect(await strategyCandidate.getUserVotes(signer2.getAddress())).to.equal(signer2Balance);

      const [address, , , , absoluteTotalVotes, totalVotes] = await strategyCandidate.getStrategyDetails();

      // The stake is counted as votes of the strategists
      expect(absoluteTotalVotes).to.equal(totalVotes);
      // TODO: fix
      // expect(totalVotes).to.equal(ethers.utils.parseEther('5.5'));

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
          .resolveVoting(
            [signer1.getAddress(), signer2.getAddress()],
            [signer1Balance, signer2Balance],
            signer1Balance.add(signer2Balance).toString(),
            signer1Balance.add(signer2Balance).toString(),
            42,
            {
              gasPrice: 0,
            },
          ),
      ).to.be.revertedWith(/revert BAB#043/i);
    });

    it("can't push voting results twice", async function () {
      const signer1Balance = await garden2.balanceOf(signer1.getAddress());
      const signer2Balance = await garden2.balanceOf(signer2.getAddress());

      await strategyCandidate
        .connect(keeper)
        .resolveVoting(
          [signer1.getAddress(), signer2.getAddress()],
          [signer1Balance, signer2Balance],
          signer1Balance.add(signer2Balance).toString(),
          signer1Balance.add(signer2Balance).toString(),
          42,
          {
            gasPrice: 0,
          },
        );

      await expect(
        strategyCandidate
          .connect(keeper)
          .resolveVoting(
            [signer1.getAddress(), signer2.getAddress()],
            [signer1Balance, signer2Balance],
            signer1Balance.add(signer2Balance).toString(),
            signer1Balance.add(signer2Balance).toString(),
            42,
            {
              gasPrice: 0,
            },
          ),
      ).to.be.revertedWith(/revert BAB#042/i);
    });
  });

  describe('executeStrategy', async function () {
    it('should execute strategy', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
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

    it('should not be able to unwind an active strategy with not enough capital', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );
      await expect(strategyContract.unwindStrategy(ethers.utils.parseEther('1'))).to.be.reverted;
    });

    it('should be able to unwind an active strategy with enough capital', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );
      expect(await wethToken.balanceOf(garden1.address)).to.be.gt(ethers.utils.parseEther('2'));

      await executeStrategy(strategyContract, { amount: ONE_ETH.mul(2) });

      expect(await wethToken.balanceOf(garden1.address)).to.be.closeTo(ONE_ETH.mul(3), ONE_ETH.div(100));
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
        kyberTradeIntegration.address,
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
        kyberTradeIntegration.address,
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
        kyberTradeIntegration.address,
        garden1,
      );

      increaseTime(ONE_DAY_IN_SECONDS * 2);

      await expect(
        strategyContract.connect(keeper).executeStrategy(ONE_ETH, ONE_ETH.mul(100), {
          gasPrice: 0,
        }),
      ).to.be.revertedWith(/revert BAB#019/i);
    });
  });

  describe('getNAV', async function () {
    it('should get the NAV value of a long strategy', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
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
        addresses.balancer.pools.wethdai,
      );

      const nav = await strategyContract.getNAV();
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
      // So much slipage at Balancer 😭
      expect(nav).to.be.closeTo(ONE_ETH.mul(1), ONE_ETH.div(50));
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
        addresses.oneinch.pools.wethdai,
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
        addresses.uniswap.pairs.wethdai,
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
        kyberTradeIntegration.address,
        garden1,
      );

      expect(await wethToken.balanceOf(garden1.address)).to.be.closeTo(ONE_ETH.mul(5), ONE_ETH.div(100));

      await executeStrategy(strategyContract, { fee: ONE_ETH, amount: ONE_ETH.mul(4) });
      expect(await garden1.keeperDebt()).to.equal(ONE_ETH);
      expect(await wethToken.balanceOf(garden1.address)).to.be.closeTo(ONE_ETH.mul(1), ONE_ETH.div(50));

      // add extra WETH to repay keeper
      await garden1.connect(signer1).deposit(ONE_ETH.mul(2), 1, signer1.address, {
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
        kyberTradeIntegration.address,
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
        kyberTradeIntegration.address,
        garden1,
      );

      await finalizeStrategy(strategyContract);

      await expect(strategyContract.finalizeStrategy(42, 'http://', { gasPrice: 0 })).to.be.reverted;
    });
  });
});
