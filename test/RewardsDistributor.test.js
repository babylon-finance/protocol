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

  describe('Calculating BABL Rewards', async function () {
    it('should calculate correct BABL in case of strategy in less than a quarter', async function () {
      const time = new Date();
      console.log('timestamp js', time.getTime());
      //console.log('timestamp', (await strategy.enteredAt()).toString());
    
      const initialProtocol = await rewardsDistributor.checkProtocol(time.getTime());
      const initialProtocolPrincipal = initialProtocol[0];
      const initialProtocolPower = initialProtocol[4];

      console.log('INIT PROTOCOL PPAL', initialProtocolPrincipal.toString());
      console.log('INIT PROTOCOL POWER', initialProtocolPower.toString());


      const strategyContract = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );
      // It is executed
      await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('1'), 42);
      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyContract.getStrategyState();
      // Should be active
      expect(address).to.equal(strategyContract.address);
      expect(active).to.equal(true);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.not.equal(0);
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);

      // Protocol principal should be incremented accordingly
      const protocol2 = await rewardsDistributor.checkProtocol(executedAt);
      const protocolPrincipal2 = protocol2[0];
      const protocolTime2 = protocol2[1];
      const protocolquarterBelonging2 = protocol2[2];
      const protocolTimeListPointer2 = protocol2[3];
      const protocolPower2 = protocol2[4];
      //console.log('AFTER EXECUTING This is the protocolPrincipal',protocolPrincipal2.toString());
      //console.log('AFTER EXECUTING This is the protocolTime',protocolTime2.toString());
      //console.log('AFTER EXECUTING This is the protocolquarterBelonging',protocolquarterBelonging2.toString());
      //console.log('AFTER EXECUTINGThis is the protocolTimeListPointer',protocolTimeListPointer2.toString());
      //console.log('AFTER EXECUTING This is the protocolPower',protocolPower2.toString());

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      await finalizeStrategy(garden1, strategyContract, 42);
      const [address2, active2, dataSet2, finalized2, executedAt2, exitedAt2] = await strategyContract.getStrategyState();

      expect(address2).to.equal(strategyContract.address);
      expect(active2).to.equal(false);
      expect(dataSet2).to.equal(true);
      expect(finalized2).to.equal(true);
      expect(executedAt2).to.not.equal(0);
      expect(exitedAt2).to.not.equal(0);

      // Protocol principal should be reduced accordingly
      const protocol3 = await rewardsDistributor.checkProtocol(exitedAt2);
      const protocolPrincipal3 = protocol3[0];
      const protocolTime3 = protocol3[1];
      const protocolquarterBelonging3 = protocol3[2];
      const protocolTimeListPointer3 = protocol3[3];
      const protocolPower3 = protocol3[4];
      //console.log('AFTER FINALIZING This is the protocolPrincipal',protocolPrincipal3.toString());
      //console.log('AFTER This is the protocolTime',protocolTime2.toString());
      //console.log('AFTER This is the protocolquarterBelonging',protocolquarterBelonging2.toString());
      //console.log('AFTER This is the protocolTimeListPointer',protocolTimeListPointer2.toString());
      //console.log('AFTER FINALIZING is the protocolPower',protocolPower3.toString());


    });

  });

});
