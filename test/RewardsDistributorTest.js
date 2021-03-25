// We import Chai to use its asserting functions here.

const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { EMPTY_BYTES, ONE_DAY_IN_SECONDS } = require('../utils/constants');
const { loadFixture } = waffle;

const addresses = require('../utils/addresses');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');
const { BigNumber } = require('@ethersproject/bignumber');

// `describe` is a Mocha function that allows you to organize your tests. It's
// not actually needed, but having your tests organized makes debugging them
// easier. All Mocha functions are available in the global scope.

// `describe` receives the name of a section of your test suite, and a callback.
// The callback must define the tests of that section. This callback can't be
// an async function.
describe('BABL Rewards Distributor', function () {
  // Mocha has four functions that let you hook into the the test runner's
  // lifecyle. These are: `before`, `beforeEach`, `after`, `afterEach`.

  // They're very useful to setup the environment for tests, and to clean it
  // up after they run.

  // A common pattern is to declare some variables, and assign them in the
  // `before` and `beforeEach` callbacks.

  let controller;
  let bablToken;
  let rewardsSupplySchedule;
  let rewardsDistributor;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let userSigner3;
  let garden1;
  let garden2;
  let garden3;
  let strategy;
  let weth;
  let balancerIntegration;

  // `beforeEach` will run before each test, re-deploying the contract every
  // time. It receives a callback, which can be async.

  beforeEach(async () => {
    const {
      babController,
      bablToken,
      rewardsSupplySchedule,
      rewardsDistributor,
      owner,
      signer1,
      signer2,
      signer3,
      gardens,
      strategies,
      integrations,
    } = await loadFixture(deployFolioFixture);

    balancerIntegration = integrations.balancerIntegration;
    controller = babController;
    token = bablToken;
    supply = rewardsSupplySchedule;
    distributor = rewardsDistributor;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;
    garden1 = gardens.one;
    garden2 = gardens.two;
    garden3 = gardens.three;
    strategy = strategies;
    weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
    strategy = await ethers.getContractAt('Strategy', strategies[0]);
  });

  // You can nest describe calls to create subsections.
  describe('Deployment', function () {
    // `it` is another Mocha function. This is the one you use to define your
    // tests. It receives the test name, and a callback function.

    it('should successfully deploy BABL Rewards Supply Schedule contract', async function () {
      const deployedc2 = await supply.deployed();
      expect(!!deployedc2).to.equal(true);
    });

    it('should successfully deploy BABL Rewards Distributor contract', async function () {
      const deployedc = await distributor.deployed(supply.address, '50');
      expect(!!deployedc).to.equal(true);
    });
  });

  describe('Gardens construction', async function () {
    it('should have expected properties upon deployment of Garden 1', async function () {
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
    it('should have expected properties upon deployment of Garden 2', async function () {
      expect(await garden2.totalContributors()).to.equal(2); //TODO CHECK
      expect(await garden2.creator()).to.equal(await userSigner1.getAddress());
      expect(await garden2.controller()).to.equal(controller.address);
      expect(await garden2.strategyCooldownPeriod()).to.equal(ONE_DAY_IN_SECONDS);
      expect(await garden2.strategyCreatorProfitPercentage()).to.equal(ethers.utils.parseEther('0.13'));
      expect(await garden2.strategyVotersProfitPercentage()).to.equal(ethers.utils.parseEther('0.05'));
      expect(await garden2.gardenCreatorProfitPercentage()).to.equal(ethers.utils.parseEther('0.02'));
      expect(await garden2.minVotersQuorum()).to.equal(ethers.utils.parseEther('0.10'));
      expect(await garden2.minIdeaDuration()).to.equal(ONE_DAY_IN_SECONDS * 3);
      expect(await garden2.maxIdeaDuration()).to.equal(ONE_DAY_IN_SECONDS * 365);
    });

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
      expect(contributor.totalCurrentPrincipal).to.equal(ethers.utils.parseEther('1'));
      expect(contributor.tokensReceived).to.equal(supplyAfter.sub(supplyBefore));
      expect(contributor.averageDepositPrice).to.equal(1000000000000); // Initial buy rate
      expect(contributor.timestamp).to.be.gt(0);
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

    it('a contributor should be able to add an investment strategy', async function () {
      await garden1.connect(userSigner3).deposit(ethers.utils.parseEther('1'), 1, userSigner3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
      await expect(
        garden1.connect(userSigner3).addStrategy(
          ethers.utils.parseEther('10'),
          ethers.utils.parseEther('0.001'),
          ONE_DAY_IN_SECONDS * 30,
          ethers.utils.parseEther('0.05'), // 5%
          ethers.utils.parseEther('1'),
        ),
      ).to.not.be.reverted;
    });
  });

  describe('Strategies', async function () {
    it('should return the expected strategy properties getStrategyDetails()', async function () {
      const [
        address,
        strategist,
        integration,
        stake,
        absoluteTotalVotes,
        capitalAllocated,
        duration,
        expectedReturn,
        maxCapitalRequested,
        minRebalanceCapital,
        enteredAt,
      ] = await strategy.getStrategyDetails();

      expect(address).to.equal(strategy.address);
      expect(strategist).to.equal(userSigner1.address);
      expect(integration).to.not.equal(addresses.zero);
      expect(stake).to.equal(ethers.utils.parseEther('5'));
      expect(absoluteTotalVotes).to.equal(5000000);
      expect(capitalAllocated).to.equal(ethers.BigNumber.from(0));
      expect(duration).to.equal(ethers.BigNumber.from(ONE_DAY_IN_SECONDS * 30));
      expect(expectedReturn).to.equal(ethers.utils.parseEther('0.05'));
      expect(maxCapitalRequested).to.equal(ethers.utils.parseEther('10'));
      expect(minRebalanceCapital).to.equal(ethers.utils.parseEther('1'));
      expect(enteredAt.isZero()).to.equal(false);
    });

    it('should return the expected strategy state getStrategyState()', async function () {
      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategy.getStrategyState();

      expect(address).to.equal(strategy.address);
      expect(active).to.equal(false);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.equal(ethers.BigNumber.from(0));
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));
    });
  });
  /** 
  describe('Rewards Supply Schedule', async function () {
    it('should return the expected Supply Schedule', async function () {
      // Check first EPOCH supply
      const value = ethers.utils.parseEther('1');
      const value2 = ethers.utils.parseEther('53571428571428600000000');
      expect(await supply.connect(ownerSigner).tokenSupplyPerQuarter(value)).to.equal(value2);

      // Check EPOCH nº10 supply
      //const value3 = ethers.utils.parseEther('5');
      //const value4 = ethers.utils.parseEther('19318394195441783070605');
      //expect(await supply.connect(ownerSigner).tokenSupplyPerQuarter(value3)).to.equal(value4);
    });
  });
  */
});
