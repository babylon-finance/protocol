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
  let babController;
  let bablToken;
  let rewardsDistributor;
  let rewardsSupplySchedule;
  let strategyDataset;
  let strategyCandidate;
  let signer1;
  let signer2;
  let signer3;
  let garden1;
  let garden2;
  let garden3;
  let weth;
  let strategy11;
  let strategy21;
  let balancerIntegration;


  beforeEach(async () => {
    ({ babController, bablToken, signer1, garden1, garden2, garden3, strategy11, strategy21, signer2, signer3, balancerIntegration, rewardsDistributor, rewardsSupplySchedule } = await loadFixture(deployFolioFixture));

    weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
    strategyDataset = await ethers.getContractAt('Strategy', strategy11);
    strategyCandidate = await ethers.getContractAt('Strategy', strategy21);
  });

  // You can nest describe calls to create subsections.
  describe('Deployment', function () {
    // `it` is another Mocha function. This is the one you use to define your
    // tests. It receives the test name, and a callback function.

    it('should successfully deploy BABL Mining Rewards Supply Schedule contract', async function () {
      const deployedc2 = await rewardsSupplySchedule.deployed();
      expect(!!deployedc2).to.equal(true);
    });

    it('should successfully deploy BABL Mining Rewards Distributor contract', async function () {
      const deployedc = await rewardsDistributor.deployed(rewardsSupplySchedule.address, '50');
      expect(!!deployedc).to.equal(true);
    });
  });

  describe('Garden construction', async function () {
    it('should have expected properties upon deployment', async function () {
      expect(await garden1.totalContributors()).to.equal(1);
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      expect(await garden1.controller()).to.equal(babController.address);
      expect(await garden1.strategyCooldownPeriod()).to.equal(ONE_DAY_IN_SECONDS);
      expect(await garden1.strategyCreatorProfitPercentage()).to.equal(ethers.utils.parseEther('0.13'));
      expect(await garden1.strategyVotersProfitPercentage()).to.equal(ethers.utils.parseEther('0.05'));
      expect(await garden1.gardenCreatorProfitPercentage()).to.equal(ethers.utils.parseEther('0.02'));
      expect(await garden1.minVotersQuorum()).to.equal(ethers.utils.parseEther('0.10'));
      expect(await garden1.minIdeaDuration()).to.equal(ONE_DAY_IN_SECONDS * 3);
      expect(await garden1.maxIdeaDuration()).to.equal(ONE_DAY_IN_SECONDS * 365);
    });
  });
  
});
