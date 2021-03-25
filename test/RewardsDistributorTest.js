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

  let bablToken;
  let rewardsSupplySchedule;
  let rewardsDistributor;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let userSigner3;

  // `beforeEach` will run before each test, re-deploying the contract every
  // time. It receives a callback, which can be async.

  beforeEach(async () => {
    const { bablToken, rewardsSupplySchedule, rewardsDistributor, owner, signer1, signer2, signer3 } = await loadFixture(deployFolioFixture);

    token = bablToken;
    supply = rewardsSupplySchedule;
    distributor = rewardsDistributor;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;

    // console.log(
    //   "Config:",
    //   oracle,
    //   valuer,
    //   ownerSigner,
    //   userSigner1,
    //   userSigner2,
    //   userSigner3
    // );
  });

  // You can nest describe calls to create subsections.
  describe('Deployment', function () {
    // `it` is another Mocha function. This is the one you use to define your
    // tests. It receives the test name, and a callback function.

    it('should successfully deploy Rewards Supply Schedule contract', async function () {
      const deployedc2 = await supply.deployed();
      expect(!!deployedc2).to.equal(true);
    });

    it('should successfully deploy BABL Rewards Distributor contract', async function () {
      const deployedc = await distributor.deployed(supply.address, "50");
      expect(!!deployedc).to.equal(true);
    });

    
  });
});
