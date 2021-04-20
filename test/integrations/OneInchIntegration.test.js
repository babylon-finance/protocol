const { expect } = require('chai');
// const superagent = require('superagent');
const { waffle, ethers } = require('hardhat');
const { deployFolioFixture } = require('../fixtures/ControllerFixture');
const { createStrategy, executeStrategy, finalizeStrategy } = require('../fixtures/StrategyHelper');
const addresses = require('../../utils/addresses');

const { loadFixture } = waffle;

describe('OneInchTradeIntegration', function () {
  let oneInchTradeIntegration;
  let garden1;
  let babController;
  let signer1;
  let signer2;
  let signer3;

  beforeEach(async () => {
    ({ babController, garden1, oneInchTradeIntegration, signer1, signer2, signer3 } = await loadFixture(
      deployFolioFixture,
    ));
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
      const strategyContract = await createStrategy(
        'long',
        'vote',
        [signer1, signer2, signer3],
        oneInchTradeIntegration.address,
        garden1,
      );

      await executeStrategy(strategyContract);
      expect(await daiToken.balanceOf(strategyContract.address)).to.be.gt(ethers.utils.parseEther('900') / 10 ** 12);

      await finalizeStrategy(strategyContract, 0);
      expect(await daiToken.balanceOf(strategyContract.address)).to.equal(0);
      expect(await wethToken.balanceOf(garden1.address)).to.equal('3085000000000000000'); // 1.085 ETH
    });
  });
});
