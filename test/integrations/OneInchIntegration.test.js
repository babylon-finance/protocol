const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ONE_ETH } = require('../../lib/constants');
const { setupTests } = require('../fixtures/GardenFixture');
const {
  createStrategy,
  DEFAULT_STRATEGY_PARAMS,
  executeStrategy,
  finalizeStrategy,
} = require('../fixtures/StrategyHelper');
const addresses = require('../../lib/addresses');

describe('OneInchTradeIntegration', function () {
  let oneInchTradeIntegration;
  let garden1;
  let babController;
  let signer1;
  let signer2;
  let signer3;

  beforeEach(async () => {
    ({ babController, garden1, oneInchTradeIntegration, signer1, signer2, signer3 } = await setupTests()());
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      const deployedOne = await oneInchTradeIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedOne).to.equal(true);
    });
  });

  describe('Trading', function () {
    let daiToken;
    let wethToken;

    beforeEach(async () => {
      daiToken = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
      wethToken = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
    });

    it('trade WETH to DAI', async function () {
      const balanceBeforeStarting = await wethToken.balanceOf(garden1.address);
      expect(balanceBeforeStarting).to.equal(ethers.utils.parseEther('1.0'));
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        oneInchTradeIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        addresses.tokens.DAI,
      );
      // Got the initial deposit 1 ETH + 4ETH from voters minus the 2 ETH from the fee
      expect(await wethToken.balanceOf(garden1.address)).to.equal(ONE_ETH.mul(5));
      expect(await wethToken.balanceOf(strategyContract.address)).to.equal(0);
      await executeStrategy(strategyContract);
      // Just below 2
      expect(await wethToken.balanceOf(garden1.address)).to.be.closeTo(ONE_ETH.mul(4), ONE_ETH.div(100));
      expect(await wethToken.balanceOf(strategyContract.address)).to.equal(0);
      expect(await daiToken.balanceOf(strategyContract.address)).to.be.gt(ethers.utils.parseEther('900') / 10 ** 12);
      await finalizeStrategy(strategyContract, 0);
      expect(await daiToken.balanceOf(strategyContract.address)).to.equal(0);
      expect(await wethToken.balanceOf(garden1.address)).to.be.gt('4');
      // Sets capital returned in ETH. No profits.
      expect(await ethers.provider.getBalance(garden1.address)).to.equal(0);
    });
    // TODO: create the same test for a strategy that returns profits
  });
});
