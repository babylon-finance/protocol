const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { loadFixture } = waffle;

const addresses = require('../utils/addresses');
const { ONE_DAY_IN_SECONDS, NOW, EMPTY_BYTES } = require('../utils/constants.js');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');

describe('Garden', function () {
  let controller;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let userSigner3;
  let garden1;
  let garden2;
  let garden3;
  let weth;
  let balancerIntegration;

  beforeEach(async () => {
    const { babController, signer1, signer2, signer3, gardens, integrations, owner } = await loadFixture(
      deployFolioFixture,
    );

    balancerIntegration = integrations.balancerIntegration;
    controller = babController;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;
    garden1 = gardens.one;
    garden2 = gardens.two;
    garden3 = gardens.three;
    weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Garden construction', async function () {
    it('should have expected properties upon deployment', async function () {
      expect(await garden1.totalContributors()).to.equal(1);
      expect(await garden1.creator()).to.equal(await userSigner1.getAddress());
      expect(await garden1.controller()).to.equal(controller.address);
      expect(await garden1.strategyCooldownPeriod()).to.equal(ONE_DAY_IN_SECONDS);
      expect(await garden1.strategyCreatorProfitPercentage()).to.equal(ethers.utils.parseEther('0.13'));
      expect(await garden1.strategyVotersProfitPercentage()).to.equal(ethers.utils.parseEther('0.05'));
      expect(await garden1.gardenCreatorProfitPercentage()).to.equal(ethers.utils.parseEther('0.02'));
      expect(await garden1.minVotersQuorum()).to.equal(ethers.utils.parseEther('0.10'));
      expect(await garden1.minIdeaDuration()).to.equal(ONE_DAY_IN_SECONDS * 3);
      expect(await garden1.maxIdeaDuration()).to.equal(ONE_DAY_IN_SECONDS * 365);
    });
  });

  describe('Garden state', async function () {
    it('only the protocol should be able to update active state', async function () {
      await expect(garden1.connect(userSigner1).setActive(true)).to.be.reverted;
    });

    it('the initial deposit must be correct', async function () {
      const balance = await garden1.signer.getBalance();
      await expect(balance).to.be.gt(ethers.utils.parseEther('0.099'));
    });
  });

  describe('Garden deposit limit', async function () {
    it('reverts if the deposit is bigger than the limit', async function () {
      await expect(
        garden1.connect(userSigner3).deposit(ethers.utils.parseEther('21'), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther('21'),
        }),
      ).to.be.reverted;
    });
  });

  describe('Garden deposit disabled', async function () {
    it('reverts if the garden is disabled', async function () {
      await controller.disableGarden(garden1.address);
      await expect(
        garden1.connect(userSigner3).deposit(ethers.utils.parseEther('1'), 1, userSigner3.getAddress(), {
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
      await garden1.connect(userSigner3).deposit(ethers.utils.parseEther('1'), 1, userSigner3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      const gardenBalanceAfter = await weth.balanceOf(garden1.address);
      const supplyAfter = await garden1.totalSupply();
      // Communities
      // Manager deposit in fixture is only 0.1
      expect(supplyAfter.div(11)).to.equal(supplyBefore);
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(ethers.utils.parseEther('1'));
      expect(await garden1.totalContributors()).to.equal(2);
      expect(await garden1.getPrincipal()).to.equal(ethers.utils.parseEther('1.1'));
      expect(await garden1.getPrincipal()).to.equal(ethers.utils.parseEther('1.1'));
      const wethPosition = await garden1.getPrincipal();
      expect(wethPosition).to.be.gt(ethers.utils.parseEther('1.099'));
      // Contributor Struct
      const contributor = await garden1.contributors(userSigner3.getAddress());
      expect(contributor.lastDepositAt).to.be.gt(0);
      expect(contributor.initialDepositAt).to.be.gt(0);
      expect(contributor.numberOfOps).to.equal(1);
    });

    it('a contributor can make multiple deposits', async function () {
      await garden1.connect(userSigner3).deposit(ethers.utils.parseEther('1'), 1, userSigner3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(userSigner3).deposit(ethers.utils.parseEther('1'), 1, userSigner3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      // Note: Garden is initialized with manager as first contributor, hence the count and principal delta
      expect(await garden1.totalContributors()).to.equal(2);
      expect(await garden1.getPrincipal()).to.equal(ethers.utils.parseEther('2.1'));
    });

    it('multiple contributors can make deposits', async function () {
      await garden1.connect(userSigner3).deposit(ethers.utils.parseEther('1'), 1, userSigner3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });

      await garden1.connect(userSigner2).deposit(ethers.utils.parseEther('1'), 1, userSigner2.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });

      // Note: Garden is initialized with manager as first contributor
      expect(await garden1.totalContributors()).to.equal(3);
      expect(await garden1.getPrincipal()).to.equal(ethers.utils.parseEther('2.1'));
    });

    it('a contributor can withdraw funds if they have enough in deposits', async function () {
      await garden1.connect(userSigner3).deposit(ethers.utils.parseEther('1'), 1, userSigner3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);
      expect(await garden1.getPrincipal()).to.equal(ethers.utils.parseEther('1.1'));
      expect(await garden1.totalContributors()).to.equal(2);
      await garden1.connect(userSigner3).withdraw(90909, 1, userSigner3.getAddress());
    });

    it('a contributor cannot withdraw gardens until the time ends', async function () {
      await garden1.connect(userSigner3).deposit(ethers.utils.parseEther('1'), 1, userSigner3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      expect(await garden1.getPrincipal()).to.equal(ethers.utils.parseEther('1.1'));
      expect(await garden1.totalContributors()).to.equal(2);
      await expect(garden1.connect(userSigner3).withdraw(ethers.utils.parseEther('20'), 1, userSigner3.getAddress())).to
        .be.reverted;
    });

    it('a contributor cannot make a deposit when the garden is disabled', async function () {
      await expect(controller.disableGarden(garden1.address)).to.not.be.reverted;
      await expect(
        garden1.connect(userSigner3).deposit(ethers.utils.parseEther('1'), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther('1'),
        }),
      ).to.be.reverted;
    });

    it('a contributor cannot withdraw more comunity tokens than they have deposited', async function () {
      await garden1.connect(userSigner3).deposit(ethers.utils.parseEther('1'), 1, userSigner3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);
      expect(await garden1.getPrincipal()).to.equal(ethers.utils.parseEther('1.1'));
      expect(await garden1.totalContributors()).to.equal(2);
      await expect(garden1.connect(userSigner3).withdraw(ethers.utils.parseEther('1.12'), 2, userSigner3.getAddress()))
        .to.be.reverted;
      await expect(garden1.connect(userSigner3).withdraw(ethers.utils.parseEther('20'), 2, userSigner3.getAddress())).to
        .be.reverted;
    });
  });

  describe('Add Investment Idea', async function () {
    it('should not be able to add an investment strategy unless there is a contributor', async function () {
      await expect(
        garden1
          .connect(userSigner2)
          .addStrategy(
            ethers.utils.parseEther('10'),
            ethers.utils.parseEther('1'),
            ONE_DAY_IN_SECONDS * 15,
            EMPTY_BYTES,
            EMPTY_BYTES,
            balancerIntegration.address,
            ethers.utils.parseEther('0.05'),
            ethers.utils.parseEther('2'),
            [addresses.tokens.DAI],
            [ethers.utils.parseEther('100')],
            {
              gasLimit: 9500000,
              gasPrice: 0,
            },
          ),
      ).to.be.reverted;
    });

    it('a contributor should be able to add an investment strategy', async function () {
      await garden1.connect(userSigner3).deposit(ethers.utils.parseEther('1'), 1, userSigner3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });

      await expect(
        garden1.connect(userSigner3).addStrategy(
          ethers.utils.parseEther('10'),
          ethers.utils.parseEther('1'),
          ONE_DAY_IN_SECONDS * 30,
          ethers.utils.parseEther('0.05'), // 5%
          ethers.utils.parseEther('1'),
        ),
      ).to.not.be.reverted;
    });

    it('a contributor should not be able to add an investment strategy with a small stake', async function () {
      await garden1.connect(userSigner3).deposit(ethers.utils.parseEther('1'), 1, userSigner3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });

      await expect(
        garden1.connect(userSigner3).addStrategy(
          ethers.utils.parseEther('10'),
          ethers.utils.parseEther('0.00001'),
          ONE_DAY_IN_SECONDS * 30,
          ethers.utils.parseEther('0.05'), // 5%
          ethers.utils.parseEther('1'),
        ),
      ).to.be.reverted;
    });
  });
});
