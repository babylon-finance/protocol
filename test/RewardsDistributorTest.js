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
  let token;
  let supply;
  let distributor;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let userSigner3;
  let garden1;
  let garden2;
  let garden3;
  let strategyDataset;
  let strategyCandidate;
  let strategy11;
  let strategy21;
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
      garden1,
      garden2,
      garden3,
      strategy11,
      strategy21,
      integrationList,
    } = await loadFixture(deployFolioFixture);

    balancerIntegration = integrationList;
    controller = babController;
    token = bablToken;
    supply = rewardsSupplySchedule;
    distributor = rewardsDistributor;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;
    weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
    strategyDataset = await ethers.getContractAt('Strategy', strategy11);
    strategyCandidate = await ethers.getContractAt('Strategy', strategy21);
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
  
});
