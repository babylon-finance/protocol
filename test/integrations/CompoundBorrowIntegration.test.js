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

describe('CompoundBorrowIntegrationTest', function () {
  let compoundBorrowIntegration;
  let compoundLendIntegration;
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
      compoundLendIntegration,
      compoundBorrowIntegration,
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
      const lendDeployed = await compoundBorrowIntegration.deployed();
      expect(!!babControlerDeployed).to.equal(true);
      expect(!!lendDeployed).to.equal(true);
    });
  });

  describe('Compound Borrow', function () {
    it('can supply DAI and borrow USDC in a WETH Garden', async function () {
      const strategyContract = await createStrategy(
        'borrow',
        'vote',
        [signer1, signer2, signer3],
        [compoundLendIntegration.address, compoundBorrowIntegration.address],
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [DAI.address, USDC.address],
      );

      await executeStrategy(strategyContract);

      expect(await DAI.balanceOf(strategyContract.address)).to.equal(0);
      expect(await USDC.balanceOf(strategyContract.address)).to.be.gt(0);
      const collateral = await compoundBorrowIntegration.getCollateralBalance(strategyContract.address, DAI.address);
      expect(collateral).to.be.gt(ethers.utils.parseEther('2000'));
      expect(await compoundBorrowIntegration.getBorrowBalance(strategyContract.address, USDC.address)).to.be.gt(0);
      const beforeExitingWeth = await WETH.balanceOf(garden1.address);

      await finalizeStrategy(strategyContract);

      expect(await USDC.balanceOf(strategyContract.address)).to.equal(0);
      expect(await DAI.balanceOf(strategyContract.address)).to.equal(0);
      expect(await WETH.balanceOf(garden1.address)).to.gt(beforeExitingWeth);
    });

    it('can supply USDC and borrow DAI in a WETH Garden', async function () {
      const strategyContract = await createStrategy(
        'borrow',
        'vote',
        [signer1, signer2, signer3],
        [compoundLendIntegration.address, compoundBorrowIntegration.address],
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [USDC.address, DAI.address],
      );

      await executeStrategy(strategyContract);
      expect(await USDC.balanceOf(strategyContract.address)).to.equal(0);
      expect(await DAI.balanceOf(strategyContract.address)).to.be.gt(0);
      const collateral = await compoundBorrowIntegration.getCollateralBalance(strategyContract.address, USDC.address);
      expect(collateral).to.be.gt(2000 * 10 ** 6);
      expect(await compoundBorrowIntegration.getBorrowBalance(strategyContract.address, DAI.address)).to.be.gt(0);
      const beforeExitingWeth = await WETH.balanceOf(garden1.address);
      await finalizeStrategy(strategyContract);
      expect(await DAI.balanceOf(strategyContract.address)).to.equal(0);
      expect(await USDC.balanceOf(strategyContract.address)).to.equal(0);
      expect(await WETH.balanceOf(garden1.address)).to.gt(beforeExitingWeth);
    });

    // TODO: Add this
    // it('can supply WETH and borrow DAI in a WETH Garden', async function () {
    //   const strategyContract = await createStrategy(
    //     'borrow',
    //     'vote',
    //     [signer1, signer2, signer3],
    //     [compoundLendIntegration.address, compoundBorrowIntegration.address],
    //     garden1,
    //     DEFAULT_STRATEGY_PARAMS,
    //     [WETH.address, DAI.address],
    //   );
    //
    //   await executeStrategy(strategyContract);
    //   expect(await WETH.balanceOf(strategyContract.address)).to.equal(0);
    //   expect(await DAI.balanceOf(strategyContract.address)).to.be.gt(0);
    //   const collateral = await compoundBorrowIntegration.getCollateralBalance(strategyContract.address, WETH.address);
    //   expect(collateral).to.be.gt(1);
    //   expect(await compoundBorrowIntegration.getBorrowBalance(strategyContract.address, DAI.address)).to.be.gt(0);
    //   const beforeExitingWeth = await WETH.balanceOf(garden1.address);
    //   await finalizeStrategy(strategyContract);
    //   expect(await DAI.balanceOf(strategyContract.address)).to.equal(0);
    //   expect(await WETH.balanceOf(strategyContract.address)).to.equal(0);
    //   expect(await WETH.balanceOf(garden1.address)).to.gt(beforeExitingWeth);
    // });
  });
});
