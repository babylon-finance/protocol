const { expect } = require('chai');
const { ethers } = require('hardhat');

const addresses = require('../../lib/addresses');
const { ONE_DAY_IN_SECONDS, ONE_ETH, NOW } = require('../../lib/constants.js');
const { increaseTime } = require('../utils/test-helpers');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  executeStrategy,
  finalizeStrategy,
  injectFakeProfits,
} = require('../fixtures/StrategyHelper');

const { setupTests } = require('../fixtures/GardenFixture');

describe('Garden', function () {
  let babController;
  let rewardsDistributor;
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let garden1;
  let weth;
  let balancerIntegration;
  let kyberTradeIntegration;

  beforeEach(async () => {
    ({
      babController,
      rewardsDistributor,
      owner,
      signer1,
      signer2,
      signer3,
      garden1,
      balancerIntegration,
      kyberTradeIntegration,
    } = await setupTests()());

    weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Garden construction', async function () {
    it('should have expected properties upon deployment', async function () {
      expect(await garden1.totalContributors()).to.equal(1);
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      expect(await garden1.controller()).to.equal(babController.address);
      expect(await garden1.strategyCooldownPeriod()).to.equal(ONE_DAY_IN_SECONDS);
      expect(await garden1.minVotersQuorum()).to.equal(ethers.utils.parseEther('0.10'));
      expect(await garden1.minStrategyDuration()).to.equal(ONE_DAY_IN_SECONDS * 3);
      expect(await garden1.maxStrategyDuration()).to.equal(ONE_DAY_IN_SECONDS * 365);
    });
  });

  describe('getGardenTokenMintQuantity', async function () {
    it('get correct amounts of tokens if 1 ETH deposited', async function () {
      const tokens = await garden1.getGardenTokenMintQuantity(ONE_ETH, false);

      expect(tokens).to.be.equal(ONE_ETH);
    });

    it('get correct amounts of tokens if 8 ETH deposited', async function () {
      garden1.connect(signer3).deposit(ONE_ETH.mul(8), 1, signer3.getAddress(), {
        value: ONE_ETH.mul(8),
      });
      const tokens = await garden1.getGardenTokenMintQuantity(ONE_ETH.mul(2), false);
      expect(tokens).to.be.equal(ONE_ETH.mul(2));
    });

    it('get correct amounts of tokens if 8 ETH deposited and strategy is executed', async function () {
      garden1.connect(signer3).deposit(ONE_ETH.mul(8), 1, signer3.getAddress(), {
        value: ONE_ETH.mul(8),
      });

      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      await executeStrategy(strategyContract);

      const tokens = await garden1.getGardenTokenMintQuantity(ONE_ETH.mul(3), false);
      expect(tokens).to.be.closeTo(ONE_ETH.mul(3), ONE_ETH.div(100));
    });
  });

  describe('Garden state', async function () {
    it('only the protocol should be able to update active state', async function () {
      await expect(garden1.connect(signer1).setActive(true)).to.be.revertedWith('revert BAB#016');
    });

    it('the initial deposit must be correct', async function () {
      const balance = await garden1.signer.getBalance();
      await expect(balance).to.be.gt(ethers.utils.parseEther('0.099'));
    });
  });

  describe('Garden deposit limit', async function () {
    it('reverts if the deposit is bigger than the limit', async function () {
      await expect(
        garden1.connect(signer3).deposit(ethers.utils.parseEther('21'), 1, signer3.getAddress(), {
          value: ethers.utils.parseEther('21'),
        }),
      ).to.be.reverted;
    });
  });

  describe('Garden deposit disabled', async function () {
    it('reverts if the garden is disabled', async function () {
      await babController.connect(owner).disableGarden(garden1.address);
      await expect(
        garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
          value: ethers.utils.parseEther('1'),
        }),
      ).to.be.reverted;
    });
  });

  describe('Garden contributors', async function () {
    it('a contributor can make an initial deposit', async function () {
      expect(await garden1.totalContributors()).to.equal(1);
      const gardenBalance = await weth.balanceOf(garden1.address);
      const supplyBefore = await garden1.totalSupply();
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      const gardenBalanceAfter = await weth.balanceOf(garden1.address);
      const supplyAfter = await garden1.totalSupply();
      // Communities
      // Manager deposit in fixture is only 1
      expect(supplyAfter.sub(supplyBefore)).to.be.closeTo(ethers.utils.parseEther('1'), ethers.utils.parseEther('0.1'));
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(ethers.utils.parseEther('1'));
      expect(await garden1.totalContributors()).to.equal(2);
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('2'));
      const wethPosition = await garden1.principal();
      expect(wethPosition).to.be.gt(ethers.utils.parseEther('1.999'));
      // Contributor Struct
      const contributor = await garden1.contributors(signer3.getAddress());
      expect(contributor.lastDepositAt).to.be.gt(0);
      expect(contributor.initialDepositAt).to.be.gt(0);
    });

    it('a contributor can make multiple deposits', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      // Note: Garden is initialized with manager as first contributor, hence the count and principal delta
      expect(await garden1.totalContributors()).to.equal(2);
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('3'));
    });

    it('multiple contributors can make deposits', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });

      await garden1.connect(signer2).deposit(ethers.utils.parseEther('1'), 1, signer2.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });

      // Note: Garden is initialized with manager as first contributor
      expect(await garden1.totalContributors()).to.equal(3);
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('3'));
    });

    it('a contributor can withdraw funds if they have enough in deposits', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('2'));
      expect(await garden1.totalContributors()).to.equal(2);
      await garden1.connect(signer3).withdraw(90909, 1, signer3.getAddress());
    });

    it('a contributor cannot withdraw gardens until the time ends', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('2'));
      expect(await garden1.totalContributors()).to.equal(2);
      await expect(garden1.connect(signer3).withdraw(ethers.utils.parseEther('20'), 1, signer3.getAddress())).to.be
        .reverted;
    });

    it('a contributor cannot make a deposit when the garden is disabled', async function () {
      await expect(babController.connect(owner).disableGarden(garden1.address)).to.not.be.reverted;
      await expect(
        garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
          value: ethers.utils.parseEther('1'),
        }),
      ).to.be.reverted;
    });

    it('a contributor cannot withdraw more comunity tokens than they have deposited', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('2'));
      expect(await garden1.totalContributors()).to.equal(2);
      await expect(garden1.connect(signer3).withdraw(ethers.utils.parseEther('1.12'), 2, signer3.getAddress())).to.be
        .reverted;
      await expect(garden1.connect(signer3).withdraw(ethers.utils.parseEther('20'), 2, signer3.getAddress())).to.be
        .reverted;
    });

    it('strategist or voters cannot withdraw more comunity tokens than they have locked in active strategies', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // It is executed
      const signer1Balance = await garden1.balanceOf(signer1.address);
      const signer2Balance = await garden1.balanceOf(signer2.address);
      const signer1LockedBalance = await garden1.getLockedBalance(signer1.address);
      const signer2LockedBalance = await garden1.getLockedBalance(signer2.address);
      await executeStrategy(strategyContract, ethers.utils.parseEther('1'), 42);

      // Cannot withdraw locked stake amount
      await expect(
        garden1
          .connect(signer1)
          .withdraw(
            signer1Balance.sub(signer1LockedBalance).add(ethers.utils.parseEther('0.1')),
            1,
            signer1.getAddress(),
          ),
      ).to.be.reverted;
      // Cannot withdraw locked stake amount
      await expect(
        garden1
          .connect(signer2)
          .withdraw(
            signer2Balance.sub(signer2LockedBalance).add(ethers.utils.parseEther('0.1')),
            1,
            signer2.getAddress(),
          ),
      ).to.be.reverted;
    });

    it('strategist or voters can withdraw comunity tokens that were locked during strategy execution (negative profits) once they are unlocked after finishing active strategies', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // It is executed
      await executeStrategy(strategyContract, ethers.utils.parseEther('1'), 42);

      expect(await strategyContract.active()).to.equal(true);

      expect(await strategyContract.strategist()).to.equal(signer1.address);
      expect(await strategyContract.stake()).to.equal(ethers.utils.parseEther('0.1'));

      await finalizeStrategy(strategyContract, 42);

      // Can now withdraw stake amount as it is again unlocked

      await garden1.connect(signer2).withdraw(await garden1.balanceOf(signer2.address), 1, signer2.getAddress());

      const WITHDRAWsigner2Balance = await garden1.balanceOf(signer2.address);
      await expect(WITHDRAWsigner2Balance).to.be.equal(ethers.utils.parseEther('0'));
    });

    it('strategist or voters can withdraw comunity tokens that were locked during strategy execution (positive profits) once they are unlocked after finishing active strategies', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // It is executed
      await executeStrategy(strategyContract, ethers.utils.parseEther('1'), 42);

      expect(await strategyContract.active()).to.equal(true);

      expect(await strategyContract.strategist()).to.equal(signer1.address);
      expect(await strategyContract.stake()).to.equal(ethers.utils.parseEther('0.1'));

      await injectFakeProfits(strategyContract, ethers.utils.parseEther('200')); // We inject positive profits

      await finalizeStrategy(strategyContract, 42);

      // Can now withdraw stake amount as it is again unlocked
      await expect(garden1.connect(signer2).withdraw(await garden1.balanceOf(signer2.address), 1, signer2.getAddress()))
        .not.to.be.reverted;

      const WITHDRAWsigner2Balance = await garden1.balanceOf(signer2.address);
      await expect(WITHDRAWsigner2Balance).to.be.equal(ethers.utils.parseEther('0'));
    });

    it('strategist is taken the exact (quadratic) amount of stake after a negative profit strategy with negative results', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // It is executed
      await executeStrategy(strategyContract, ethers.utils.parseEther('1'), 42);

      expect(await strategyContract.active()).to.equal(true);

      expect(await strategyContract.strategist()).to.equal(signer1.address);
      expect(await strategyContract.stake()).to.equal(ethers.utils.parseEther('0.1'));
      const InitialStrategistBalance = await garden1.balanceOf(signer1.address);

      await finalizeStrategy(strategyContract, 42);

      // Being a negative profit strategy, the corresponding % of the loss is reduced (burned) from the strategists stake
      const value =
        (ethers.BigNumber.from(await strategyContract.capitalReturned()) /
          ethers.BigNumber.from(await strategyContract.capitalAllocated())) *
        ethers.BigNumber.from(await strategyContract.stake());
      const value2 = ethers.BigNumber.from(await strategyContract.stake()) - value;
      const toBurn = value2 * 1.75; // Quadratic penalty for bad strategists
      const finalStrategistBalance = await garden1.balanceOf(signer1.address);
      const finalReducedBalance = InitialStrategistBalance.toString() - toBurn.toString();
      await expect(finalStrategistBalance).to.be.closeTo(finalReducedBalance.toString(), 200);
    });
    it('strategist or voters can withdraw comunity tokens during strategy execution if they have enough unlocked amount in their balance', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );
      // It is executed
      await executeStrategy(strategyContract, ethers.utils.parseEther('1'), 42);

      await garden1.connect(signer2).deposit(ethers.utils.parseEther('5'), 1, signer2.getAddress(), {
        value: ethers.utils.parseEther('5'),
      });

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 5]); // to bypass hardlock
      const beforeBalance = await garden1.balanceOf(signer2.address);

      const lockedBalance = await garden1.getLockedBalance(signer2.address);
      await expect(garden1.connect(signer2).withdraw(beforeBalance.sub(lockedBalance), 1, signer2.getAddress()));

      const afterBalance = await garden1.balanceOf(signer2.address);
      await expect(afterBalance).to.be.equal(beforeBalance.mul(lockedBalance).div(beforeBalance));
    });
  });
  describe('Garden Balances', async function () {
    it('Garden WETH balance cannot be above deposit just after creation', async function () {
      const gardenBalance = await weth.balanceOf(garden1.address);
      expect(gardenBalance).to.be.equal(ethers.utils.parseEther('1'));
    });
  });
  describe('Contributor Power', async function () {
    it('the contributor power is calculated correctly if _to is after its last deposit (1 deposit from user)', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 0, NOW)).toString(),
      ).to.be.closeTo((499998254750568951).toString(), ethers.utils.parseEther('0.00005'));
    });
    it('the contributor power is calculated correctly if _to is after its last deposit and from = 0 (2 deposits from user)', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 0, NOW)).toString(),
      ).to.be.closeTo((666642075981618163).toString(), ethers.utils.parseEther('0.0000005'));
    });
    it('the contributor power is calculated correctly if _to is between two deposits and from = 0 (2 distanced deposits from user)', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 1);
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      const signer3Timestamp = await garden1.getContributor(signer3.address);
      const value = ethers.BigNumber.from(signer3Timestamp[1]);
      await expect(
        await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 0, value.add(4)),
      ).to.be.closeTo((166666666666666666).toString(), ethers.utils.parseEther('0.05'));
    });
    it('the contributor power is calculated correctly if _from and _to are between two deposits', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90); // Getting some unlocked tokens
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1625141663, 1625141663)
        ).toString(),
      ).to.be.closeTo((500000000000000000).toString(), ethers.utils.parseEther('0.05'));
    });
    it('the contributor power is calculated correctly if _from is between two deposits and _to after the last deposit', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });

      await increaseTime(ONE_DAY_IN_SECONDS * 1); // Getting some unlocked tokens
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });

      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365663, 1619546549)
        ).toString(),
      ).to.be.closeTo((662205878389618258).toString(), ethers.utils.parseEther('0.005'));
    });
    it('the contributor power is calculated correctly if _from and _to are 2 years after the last deposit', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 2); // Getting some unlocked tokens
      // TODO CHECK VALUES
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1682615107, 1682874307)
        ).toString(),
      ).to.be.closeTo((666666666666666666).toString(), ethers.utils.parseEther('0.000005'));
    });
    it('the contributor power is calculated correctly if _from and _to are 2 years after the last deposit but several other deposits were taking place', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 1); // Getting some unlocked tokens
      await garden1.connect(signer2).deposit(ethers.utils.parseEther('5'), 1, signer2.getAddress(), {
        value: ethers.utils.parseEther('5'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('5'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('5'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 2); // Getting some unlocked tokens
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1682615107, 1682874307)
        ).toString(),
      ).to.be.closeTo((153846155020396967).toString(), ethers.utils.parseEther('0.0005'));
    });
    it('a malicious contributor cannot make a flash loan to get maximum contributor power', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('5'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('5'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('10'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('10'),
      });
      // Despite malicious contributor deposit 10ETH to increase its position, 11ETH out of 17 ETH (64%) (conviction deposit) it only gets 15% of contribution power within the time period
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 0, 1625245507)).toString(),
      ).to.be.closeTo((142857070336142271).toString(), ethers.utils.parseEther('0.0005'));
    });
    it('a malicious contributor cannot make a flash loan to get maximum contributor power from !=0 ', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('5'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('5'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('10'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('10'),
      });
      // Despite malicious contributor deposit 10ETH to increase its position, 11ETH out of 17 ETH (64%) (conviction deposit) it only gets 15% of contribution power within the time period
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365661, 1625245507)
        ).toString(),
      ).to.be.closeTo((142857070336142271).toString(), ethers.utils.parseEther('0.0005'));
    });
    it('a malicious contributor cannot make a flash loan to get maximum contributor power (2 big deposits) ', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('5'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('5'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('5'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('5'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('5'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('5'),
      });
      // Despite malicious contributor deposit new 5ETH to increase its position, 11ETH out of 17 ETH (64%) (conviction deposit) it only gets 50% of contribution power within the time period as most of the period had 50%
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365661, 1625245507)
        ).toString(),
      ).to.be.closeTo((499999750142340207).toString(), ethers.utils.parseEther('0.0005'));
    });
    it('contributor power is calculated correctly for different users in the same garden with the same power ', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('5'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('5'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('5'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('5'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('2'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('2'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('2'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('2'),
      });
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365661, 1630602307)
        ).toString(),
      ).to.be.closeTo((499999988930846637).toString(), ethers.utils.parseEther('0.0000005'));
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer1.address, 1617365661, 1630602307)
        ).toString(),
      ).to.be.closeTo((500000002767288110).toString(), ethers.utils.parseEther('0.0000005'));
    });
    it('contributor power is calculated correctly for different users if using _from and _to exact deposit timestamps ', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('5'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('5'),
      });
      const signer3DepositTimestamp = await garden1.getContributor(signer3.address);
      const signer1DepositTimestamp = await garden1.getContributor(signer1.address);
      await expect(
        (
          await rewardsDistributor.getContributorPower(
            garden1.address,
            signer1.address,
            signer1DepositTimestamp[0],
            signer1DepositTimestamp[0],
          )
        ).toString(),
      ).to.be.closeTo((944444444444444444).toString(), ethers.utils.parseEther('0.05'));
      await expect(
        (
          await rewardsDistributor.getContributorPower(
            garden1.address,
            signer3.address,
            signer3DepositTimestamp[0],
            signer3DepositTimestamp[0],
          )
        ).toString(),
      ).to.be.equal('0');
    });
    it('contributor power is calculated correctly for different users if using _from and _to exact deposit timestamps (variation on deposits) ', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('3'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('3'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('3'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('3'),
      });
      const signer3DepositTimestamp = await garden1.getContributor(signer3.address);
      const signer1DepositTimestamp = await garden1.getContributor(signer1.address);
      await expect(
        (
          await rewardsDistributor.getContributorPower(
            garden1.address,
            signer1.address,
            signer1DepositTimestamp[1],
            signer1DepositTimestamp[1],
          )
        ).toString(),
      ).to.be.equal('0');
      await expect(
        (
          await rewardsDistributor.getContributorPower(
            garden1.address,
            signer1.address,
            signer1DepositTimestamp[0],
            signer1DepositTimestamp[0],
          )
        ).toString(),
      ).to.be.closeTo((833333333333333333).toString(), ethers.utils.parseEther('0.05'));
      await expect(
        (
          await rewardsDistributor.getContributorPower(
            garden1.address,
            signer3.address,
            signer3DepositTimestamp[0],
            signer3DepositTimestamp[0],
          )
        ).toString(),
      ).to.be.closeTo((55555555555555555).toString(), ethers.utils.parseEther('0.05'));
    });
    it('contributor power is 100% for the creator if it is the only user (1 deposit)', async function () {
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365661, 1630602307)
        ).toString(),
      ).to.be.closeTo((0).toString(), ethers.utils.parseEther('0.0000005'));
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer1.address, 1617365661, 1630602307)
        ).toString(),
      ).to.be.closeTo((1000000000000000000).toString(), ethers.utils.parseEther('0.0000005'));
    });
    it('should work well when trying to hack it using the from = to', async function () {
      await garden1.connect(signer2).deposit(ethers.utils.parseEther('1'), 1, signer2.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer2.address, 1630602307, 1630602307)
        ).toString(),
      ).to.be.closeTo((499999697808826913).toString(), ethers.utils.parseEther('0.0000005'));
    });
    it('contributor power is 100% for the creator if it is the only user (several deposits)', async function () {
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365661, 1630602307)
        ).toString(),
      ).to.be.closeTo((0).toString(), ethers.utils.parseEther('0.0000005'));
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer1.address, 1617365661, 1630602307)
        ).toString(),
      ).to.be.closeTo((1000000000000000000).toString(), ethers.utils.parseEther('0.0000005'));
    });
    it('should fail get contributor power if _to < gardenInitializedAt', async function () {
      await expect(
        rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365635, 1617365640),
      ).to.be.revertedWith('revert BAB#065');
    });
    it('should fail get contributor power if _to < _from', async function () {
      await expect(
        rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365645, 1617365640),
      ).to.be.revertedWith('revert BAB#065');
    });
    it('contributor power is 100% for the creator if it is the only user (several distanced deposits)', async function () {
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('5'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('5'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('2'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('2'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365661, 1630602307)
        ).toString(),
      ).to.be.closeTo((0).toString(), ethers.utils.parseEther('0.0000005'));
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer1.address, 1617365661, 1630602307)
        ).toString(),
      ).to.be.closeTo((1000000000000000000).toString(), ethers.utils.parseEther('0.0000005'));
    });
    it('contributor power is 40% for signer 1, 30% for signers 2 and 3', async function () {
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('0.5'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('0.5'),
      });
      await garden1.connect(signer2).deposit(ethers.utils.parseEther('1'), 1, signer2.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer2).deposit(ethers.utils.parseEther('1'), 1, signer2.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer1.address, 0, 1630602307)).toString(),
      ).to.be.closeTo((413967400713710268).toString(), ethers.utils.parseEther('0.0000005'));
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer2.address, 0, 1630602307)).toString(),
      ).to.be.closeTo((293016324178292452).toString(), ethers.utils.parseEther('0.0000005'));
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 0, 1630602307)).toString(),
      ).to.be.closeTo((298153809109203925).toString(), ethers.utils.parseEther('0.0000005'));
    });
    it('contributor power is 33%% each for 3 signers', async function () {
      await garden1.connect(signer2).deposit(ethers.utils.parseEther('1'), 1, signer2.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer2).deposit(ethers.utils.parseEther('1'), 1, signer2.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      // TODO CHECK FAIL SIGNER1 BY THE NEW FIX IN MAIN
      //await expect((await garden1.getContributorPower(signer1.address, 0, 1630602307)).toString()).to.be.closeTo((333333238251235557).toString(), ethers.utils.parseEther('0.0000005'));
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer2.address, 0, 1630602307)).toString(),
      ).to.be.closeTo((333333238251235557).toString(), ethers.utils.parseEther('0.0000005'));
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 0, 1630602307)).toString(),
      ).to.be.closeTo((333333202595448891).toString(), ethers.utils.parseEther('0.0000005'));
    });
    it('the contributor power is 0 if still not deposited in the garden', async function () {
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 0, NOW)).toString(),
      ).to.be.equal('0');
    });
    it('the contributor power is reverted if the time is before the garden initializes', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await expect(rewardsDistributor.getContributorPower(garden1.address, signer3.address, 0, 1617365660)).to.be
        .reverted;
    });
  });

  describe('Add Strategy', async function () {
    it('should not be able to add an strategy unless there is a contributor', async function () {
      await expect(
        garden1
          .connect(signer2)
          .addStrategy(
            'name',
            'STRT',
            DEFAULT_STRATEGY_PARAMS,
            [1],
            [balancerIntegration.address],
            [addresses.balancer.pools.wethdai],
            {
              gasLimit: 9500000,
              gasPrice: 0,
            },
          ),
      ).to.be.reverted;
    });

    it('a contributor should be able to add an strategy', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });

      await expect(
        garden1
          .connect(signer3)
          .addStrategy(
            'name',
            'STRT',
            DEFAULT_STRATEGY_PARAMS,
            [1],
            [balancerIntegration.address],
            [addresses.balancer.pools.wethdai],
          ),
      ).to.not.be.reverted;
    });

    it('a contributor should not be able to add an strategy with a small stake', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      const params = [...DEFAULT_STRATEGY_PARAMS];
      params[1] = ethers.utils.parseEther('0');

      await expect(
        garden1
          .connect(signer3)
          .addStrategy('name', 'STRT', params, [1], [balancerIntegration.address], [addresses.balancer.pools.wethdai]),
      ).to.be.reverted;
    });
  });
});
