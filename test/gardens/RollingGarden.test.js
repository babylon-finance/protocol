const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { loadFixture } = waffle;

const addresses = require('../../utils/addresses');
const { ONE_DAY_IN_SECONDS } = require('../../utils/constants.js');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  executeStrategy,
  finalizeStrategy,
  injectFakeProfits,
} = require('../fixtures/StrategyHelper');
const { deployFolioFixture } = require('../fixtures/ControllerFixture');

describe('Garden', function () {
  let babController;
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
      signer1,
      signer2,
      signer3,
      garden1,
      balancerIntegration,
      kyberTradeIntegration,
    } = await loadFixture(deployFolioFixture));

    weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Garden construction', async function () {
    it('should have expected properties upon deployment', async function () {
      expect(await garden1.totalContributors()).to.equal(1);
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      expect(await garden1.controller()).to.equal(babController.address);
      expect(await garden1.strategyCooldownPeriod()).to.equal(ONE_DAY_IN_SECONDS);
      expect(await garden1.minVotersQuorum()).to.equal(ethers.utils.parseEther('0.10'));
      expect(await garden1.minIdeaDuration()).to.equal(ONE_DAY_IN_SECONDS * 3);
      expect(await garden1.maxIdeaDuration()).to.equal(ONE_DAY_IN_SECONDS * 365);
    });
  });

  describe('Garden state', async function () {
    it('only the protocol should be able to update active state', async function () {
      await expect(garden1.connect(signer1).setActive()).to.be.reverted;
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
      await babController.disableGarden(garden1.address);
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
      // Manager deposit in fixture is only 0.1
      expect(supplyAfter.div(11)).to.equal(supplyBefore);
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(ethers.utils.parseEther('1'));
      expect(await garden1.totalContributors()).to.equal(2);
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('1.1'));
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('1.1'));
      const wethPosition = await garden1.principal();
      expect(wethPosition).to.be.gt(ethers.utils.parseEther('1.099'));
      // Contributor Struct
      const contributor = await garden1.contributors(signer3.getAddress());
      expect(contributor.lastDepositAt).to.be.gt(0);
      expect(contributor.initialDepositAt).to.be.gt(0);
      expect(contributor.numberOfOps).to.equal(1);
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
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('2.1'));
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
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('2.1'));
    });

    it('a contributor can withdraw funds if they have enough in deposits', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('1.1'));
      expect(await garden1.totalContributors()).to.equal(2);
      await garden1.connect(signer3).withdraw(90909, 1, signer3.getAddress());
    });

    it('a contributor cannot withdraw gardens until the time ends', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('1.1'));
      expect(await garden1.totalContributors()).to.equal(2);
      await expect(garden1.connect(signer3).withdraw(ethers.utils.parseEther('20'), 1, signer3.getAddress())).to.be
        .reverted;
    });

    it('a contributor cannot make a deposit when the garden is disabled', async function () {
      await expect(babController.disableGarden(garden1.address)).to.not.be.reverted;
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
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('1.1'));
      expect(await garden1.totalContributors()).to.equal(2);
      await expect(garden1.connect(signer3).withdraw(ethers.utils.parseEther('1.12'), 2, signer3.getAddress())).to.be
        .reverted;
      await expect(garden1.connect(signer3).withdraw(ethers.utils.parseEther('20'), 2, signer3.getAddress())).to.be
        .reverted;
    });

    it('strategist or voters cannot withdraw more comunity tokens than they have locked in active strategies', async function () {
      const strategyContract = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // It is executed
      await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42);

      // Cannot withdraw locked stake amount
      await expect(garden1.connect(signer1).withdraw(ethers.utils.parseEther('1.2'), 1, signer1.getAddress())).to.be
        .reverted;
      // Cannot withdraw locked stake amount
      await expect(garden1.connect(signer2).withdraw(ethers.utils.parseEther('1.2'), 1, signer1.getAddress())).to.be
        .reverted;
    });
    it('strategist or voters can withdraw comunity tokens that were locked during strategy execution (negative profits) once they are unlocked after finishing active strategies', async function () {
      const strategyContract = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // It is executed
      await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42);

      expect(await strategyContract.active()).to.equal(true);

      expect(await strategyContract.strategist()).to.equal(signer1.address);
      expect(await strategyContract.stake()).to.equal(ethers.utils.parseEther('1'));

      await finalizeStrategy(garden1, strategyContract, 42);

      // Can now withdraw stake amount as it is again unlocked
      await expect(garden1.connect(signer1).withdraw(ethers.utils.parseEther('0.1'), 1, signer1.getAddress())).not.to.be
        .reverted;
      await expect(garden1.connect(signer2).withdraw(ethers.utils.parseEther('1.1'), 1, signer2.getAddress())).not.to.be
        .reverted;

      const WITHDRAWsigner2Balance = await garden1.balanceOf(signer2.address);
      await expect(WITHDRAWsigner2Balance).to.be.equal(ethers.utils.parseEther('0.9'));
    });

    it('strategist or voters can withdraw comunity tokens that were locked during strategy execution (positive profits) once they are unlocked after finishing active strategies', async function () {
      const strategyContract = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // It is executed
      await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42);

      expect(await strategyContract.active()).to.equal(true);

      expect(await strategyContract.strategist()).to.equal(signer1.address);
      expect(await strategyContract.stake()).to.equal(ethers.utils.parseEther('1'));

      await injectFakeProfits(strategyContract, ethers.utils.parseEther('200')); // We inject positive profits

      await finalizeStrategy(garden1, strategyContract, 42);

      // Can now withdraw stake amount as it is again unlocked
      await expect(garden1.connect(signer1).withdraw(ethers.utils.parseEther('0.1'), 1, signer1.getAddress())).not.to.be
        .reverted;
      await expect(garden1.connect(signer2).withdraw(ethers.utils.parseEther('1.1'), 1, signer2.getAddress())).not.to.be
        .reverted;

      const WITHDRAWsigner2Balance = await garden1.balanceOf(signer2.address);
      await expect(WITHDRAWsigner2Balance).to.be.equal(ethers.utils.parseEther('0.9'));
    });

    it('strategist is taken the exact amount of stake after a negative profit strategy with negative results', async function () {
      const strategyContract = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      // It is executed
      await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42);

      expect(await strategyContract.active()).to.equal(true);

      expect(await strategyContract.strategist()).to.equal(signer1.address);
      expect(await strategyContract.stake()).to.equal(ethers.utils.parseEther('1'));

      await finalizeStrategy(garden1, strategyContract, 42);

      // Being a negative profit strategy, the corresponding % of the loss is reduced (burned) from the strategists stake
      const value =
        (ethers.BigNumber.from(await strategyContract.capitalReturned()) /
          ethers.BigNumber.from(await strategyContract.capitalAllocated())) *
        ethers.BigNumber.from(await strategyContract.stake());

      const finalStrategistBalance = await garden1.balanceOf(signer1.address);
      const finalReducedStrategistBalance = finalStrategistBalance - ethers.utils.parseEther('1.1');

      await expect(finalReducedStrategistBalance).to.be.closeTo(value, 100);
    });

    it('strategist or voters can withdraw comunity tokens during strategy execution if they have enough unlocked amount in their balance', async function () {
      const strategyContract = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );
      // It is executed
      await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42);

      await garden1.connect(signer2).deposit(ethers.utils.parseEther('5'), 1, signer2.getAddress(), {
        value: ethers.utils.parseEther('5'),
      });

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 5]); // to bypass hardlock

      await expect(garden1.connect(signer2).withdraw(ethers.utils.parseEther('5'), 1, signer2.getAddress()));

      const WITHDRAWsigner2Balance = await garden1.balanceOf(signer2.address);
      await expect(WITHDRAWsigner2Balance).to.be.equal(ethers.utils.parseEther('2'));
    });
  });

  describe('Add Strategy', async function () {
    it('should not be able to add an strategy unless there is a contributor', async function () {
      await expect(
        garden1.connect(signer2).addStrategy(
          0,
          balancerIntegration.address,
          ethers.utils.parseEther('10'),
          ethers.utils.parseEther('5'),
          ONE_DAY_IN_SECONDS * 30,
          ethers.utils.parseEther('0.05'), // 5%
          ethers.utils.parseEther('1'),
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
          .addStrategy(0, balancerIntegration.address, ...DEFAULT_STRATEGY_PARAMS, addresses.balancer.pools.wethdai),
      ).to.not.be.reverted;
    });

    it('a contributor should not be able to add an strategy with a small stake', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });

      await expect(garden1.connect(signer3).addStrategy(0, balancerIntegration.address, DEFAULT_STRATEGY_PARAMS)).to.be
        .reverted;
    });
  });
});
