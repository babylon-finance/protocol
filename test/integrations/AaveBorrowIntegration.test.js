const { expect } = require('chai');
const { ethers } = require('hardhat');
const {
  createStrategy,
  executeStrategy,
  finalizeStrategy,
  DEFAULT_STRATEGY_PARAMS,
} = require('../fixtures/StrategyHelper');
const { setupTests } = require('../fixtures/GardenFixture');
const addresses = require('../../lib/addresses');

describe('AaveBorrowIntegrationTest', function () {
  let aaveBorrowIntegration;
  let aaveLendIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let babController;
  let USDC;
  let DAI;
  let WETH;

  beforeEach(async () => {
    ({
      garden1,
      babController,
      aaveLendIntegration,
      aaveBorrowIntegration,
      signer1,
      signer2,
      signer3,
    } = await setupTests()());
    USDC = await ethers.getContractAt('IERC20', addresses.tokens.USDC);
    DAI = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
    WETH = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const babControlerDeployed = await babController.deployed();
      const lendDeployed = await aaveBorrowIntegration.deployed();
      expect(!!babControlerDeployed).to.equal(true);
      expect(!!lendDeployed).to.equal(true);
    });
  });

  describe('Aave Borrow', function () {
    it.only('can supply DAI and borrow USDC in a WETH Garden', async function () {
      const strategyContract = await createStrategy(
        'borrow',
        'vote',
        [signer1, signer2, signer3],
        [aaveLendIntegration.address, aaveBorrowIntegration.address],
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [DAI.address, USDC.address],
      );

      await executeStrategy(strategyContract);
      expect(await DAI.balanceOf(strategyContract.address)).to.equal(0);
      expect(await USDC.balanceOf(strategyContract.address)).to.be.gt(0);
      const beforeExitingWeth = await WETH.balanceOf(strategyContract.address);
      await finalizeStrategy(strategyContract);
      expect(await USDC.balanceOf(strategyContract.address)).to.equal(0);
      expect(await DAI.balanceOf(strategyContract.address)).to.be.gt(0);
      expect(await WETH.balanceOf(strategyContract.address)).to.gt(beforeExitingWeth);
    });
  });
});
