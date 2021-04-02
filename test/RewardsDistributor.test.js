// We import Chai to use its asserting functions here.

const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { EMPTY_BYTES, ONE_DAY_IN_SECONDS } = require('../utils/constants');
const { loadFixture } = waffle;

const { createStrategy, executeStrategy, finalizeStrategy } = require('./fixtures/StrategyHelper.js');

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
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let babController;
  let bablToken;
  let rewardsDistributor;
  let garden1;
  let garden2;
  let strategy11;
  let strategy11Contract;
  let strategy21;
  let strategy21Contract;
  let weth;
  let kyberTradeIntegration;


  beforeEach(async () => {
    ({
      owner,
      signer1,
      signer2,
      signer3,
      garden1,
      garden2,
      strategy11,
      strategy21,
      babController,
      bablToken,
      rewardsDistributor,
      kyberTradeIntegration,
    } = await loadFixture(deployFolioFixture));

    wethToken = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
    strategy11Contract = await ethers.getContractAt('Strategy', strategy11);
    strategy21Contract = await ethers.getContractAt('Strategy', strategy21);
  });

  // You can nest describe calls to create subsections.
  describe('Deployment', function () {
    // `it` is another Mocha function. This is the one you use to define your
    // tests. It receives the test name, and a callback function.

    it('should successfully deploy BABL Mining Rewards Distributor contract', async function () {
      const deployedc = await rewardsDistributor.deployed(bablToken.address, babController.address);
      expect(!!deployedc).to.equal(true);
    });
  });

  describe('Protocol power control', async function () {
    it('should increment protocol power when executing a new strategy', async function () {
      
      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategy11Contract.getStrategyState();
      // Protocol principal check before test based on controller fixture
      const protocol = await rewardsDistributor.checkProtocol(executedAt);
      const protocolPrincipal = protocol[0];
      const protocolTime = protocol[1];
      const protocolquarterBelonging = protocol[2];
      const protocolTimeListPointer = protocol[3];
      const protocolPower = protocol[4];
      console.log('BEFORE This is the protocolPrincipal',protocolPrincipal.toString());
      console.log('BEFORE This is the protocolTime',protocolTime.toString());
      console.log('BEFORE This is the protocolquarterBelonging',protocolquarterBelonging.toString());
      console.log('BEFORE This is the protocolTimeListPointer',protocolTimeListPointer.toString());
      console.log('BEFORE This is the protocolPower',protocolPower.toString());
      
      const strategyContract = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );
      // It is executed
      await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42);
      const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await strategyContract.getStrategyState();
      // Should be active
      expect(address2).to.equal(strategyContract.address);
      expect(active2).to.equal(true);
      expect(dataSet2).to.equal(true);
      expect(finalized2).to.equal(false);
      expect(executedAt2).to.not.equal(0);
      expect(exitedAt2).to.equal(ethers.BigNumber.from(0));

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);

      // Protocol principal should be incremented in 42
      const protocol2 = await rewardsDistributor.checkProtocol(executedAt2);
      const protocolPrincipal2 = protocol2[0];
      const protocolTime2 = protocol2[1];
      const protocolquarterBelonging2 = protocol2[2];
      const protocolTimeListPointer2 = protocol2[3];
      const protocolPower2 = protocol2[4];
      console.log('AFTER This is the protocolPrincipal',protocolPrincipal2.toString());
      console.log('AFTER This is the protocolTime',protocolTime2.toString());
      console.log('AFTER This is the protocolquarterBelonging',protocolquarterBelonging2.toString());
      console.log('AFTER This is the protocolTimeListPointer',protocolTimeListPointer2.toString());
      console.log('AFTER This is the protocolPower',protocolPower2.toString());


      //expect(userSigner1RegisteredTeam).to.equal(true);
      //expect(userSigner1RegisteredCliff).to.equal(true);
      //expect(userSigner1RegisteredVestingBegin).to.equal(1614618000);
      //expect(userSigner1RegisteredVestingEnd).to.equal(1614618000 + ONE_DAY_IN_SECONDS * 365 * 4);

    });

  });

  describe('finalizeInvestment', async function () {
    it('should finalize investment idea', async function () {
      const strategyContract = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      await finalizeStrategy(garden1, strategyContract, 42);
      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyContract.getStrategyState();

      expect(address).to.equal(strategyContract.address);
      expect(active).to.equal(false);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(true);
      expect(executedAt).to.not.equal(0);
      expect(exitedAt).to.not.equal(0);

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);
    });

    it("can't finalize investment twice", async function () {
      const strategyContract = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      await finalizeStrategy(garden1, strategyContract, 42);

      await expect(strategyContract.finalizeInvestment(42, { gasPrice: 0 })).to.be.reverted;
    });
  });
});
