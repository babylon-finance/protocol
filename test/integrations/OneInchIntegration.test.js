const { expect } = require('chai');
const { ethers } = require('hardhat');
const { setupTests } = require('../fixtures/GardenFixture');
const { createStrategy, executeStrategy, finalizeStrategy } = require('../fixtures/StrategyHelper');
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
        'long',
        'vote',
        [signer1, signer2, signer3],
        oneInchTradeIntegration.address,
        garden1,
      );
      // Got the initial deposit 1 ETH + 4ETH from voters minus the 2 ETH from the fee
      expect(await wethToken.balanceOf(garden1.address)).to.equal(ethers.utils.parseEther('2.99'));
      // Got keeper fees 2.0 ETH
      expect(await wethToken.balanceOf(strategyContract.address)).to.equal(ethers.utils.parseEther('2.0'));
      await executeStrategy(strategyContract);
      // Just below 2
      expect(await wethToken.balanceOf(garden1.address)).to.be.lt(ethers.utils.parseEther('2.0'));
      // Strategy has 2 weth from keepers still
      expect(await wethToken.balanceOf(strategyContract.address)).to.equal(ethers.utils.parseEther('2.0'));
      expect(await daiToken.balanceOf(strategyContract.address)).to.be.gt(ethers.utils.parseEther('900') / 10 ** 12);
      await finalizeStrategy(strategyContract, 0);
      expect(await daiToken.balanceOf(strategyContract.address)).to.equal(0);
      expect(await wethToken.balanceOf(garden1.address)).to.be.gt('4');
      // Sets capital returned in ETH. No profits.
      // TODO: create the same test for a strategy that returns profits
      expect(await ethers.provider.getBalance(garden1.address)).to.equal(await strategyContract.capitalReturned());
    });
  });
});
