const { expect } = require('chai');
const { ethers } = require('hardhat');
const { createStrategy, executeStrategy, finalizeStrategy } = require('../fixtures/StrategyHelper');
const { setupTests } = require('../fixtures/GardenFixture');
const addresses = require('../../lib/addresses');
const { ADDRESS_ZERO } = require('../../lib/constants');

describe('AaveLendIntegrationTest', function () {
  let aaveLendIntegration;
  let aaveBorrowIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let babController;
  let USDC;
  let WETH;

  beforeEach(async () => {
    ({ garden1, babController, aaveBorrowIntegration, aaveLendIntegration, signer1, signer2, signer3 } = await setupTests()());
    USDC = await ethers.getContractAt('IERC20', addresses.tokens.USDC);
    WETH = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const babControlerDeployed = await babController.deployed();
      const lendDeployed = await aaveLendIntegration.deployed();
      expect(!!babControlerDeployed).to.equal(true);
      expect(!!lendDeployed).to.equal(true);
    });
  });

  describe('Aave Lend', function () {
    it('can supply to valid aToken', async function () {
      expect(await aaveLendIntegration.isInvestment(addresses.tokens.USDC)).to.equal(true);
    });

    it('fails to suplly to invlaid address', async function () {
      expect(await aaveLendIntegration.isInvestment(ADDRESS_ZERO)).to.equal(false);
    });

    it('can supply and redeem tokens from Aave', async function () {
      const strategyContract = await createStrategy(
        'lend',
        'vote',
        [signer1, signer2, signer3],
        aaveLendIntegration.address,
        garden1,
      );

      await executeStrategy(strategyContract);
      expect(await USDC.balanceOf(strategyContract.address)).to.be.equal(0);
      const collateral = await aaveBorrowIntegration.getCollateralBalance(strategyContract.address, USDC.address);
      expect(collateral).to.be.gt(1);
      await finalizeStrategy(strategyContract);
      expect(await USDC.balanceOf(strategyContract.address)).to.equal(0);
      expect(await WETH.balanceOf(strategyContract.address)).to.equal(0);
      expect(await aaveBorrowIntegration.getCollateralBalance(strategyContract.address, USDC.address)).to.equal(0);
    });
    // TODO: test supply for WETH
  });
});
