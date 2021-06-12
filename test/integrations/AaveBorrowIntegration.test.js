const { expect } = require('chai');
const { ethers } = require('hardhat');
const { createStrategy, executeStrategy, finalizeStrategy } = require('../fixtures/StrategyHelper');
const { setupTests } = require('../fixtures/GardenFixture');
const addresses = require('../../lib/addresses');
const { ADDRESS_ZERO } = require('../../lib/constants');

describe('AaveBorrowIntegrationTest', function () {
  let aaveBorrowIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let babController;
  let USDC;
  let CUSDC;
  let WETH;

  beforeEach(async () => {
    ({ garden1, babController, aaveBorrowIntegration, signer1, signer2, signer3 } = await setupTests()());
    USDC = await ethers.getContractAt('IERC20', addresses.tokens.USDC);
    CUSDC = await ethers.getContractAt('IERC20', addresses.tokens.CUSDC);
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
    // it('can supply and redeem tokens from Aave', async function () {
    //   const strategyContract = await createStrategy(
    //     'lend',
    //     'vote',
    //     [signer1, signer2, signer3],
    //     aaveBorrowIntegration.address,
    //     garden1,
    //   );
    //
    //   await executeStrategy(strategyContract);
    //   expect(await USDC.balanceOf(strategyContract.address)).to.be.equal(0);
    //   expect(await CUSDC.balanceOf(strategyContract.address)).to.be.gte(0);
    //
    //   await finalizeStrategy(strategyContract);
    //   expect(await USDC.balanceOf(strategyContract.address)).to.equal(0);
    //   expect(await CUSDC.balanceOf(strategyContract.address)).to.be.equal(0);
    //   expect(await WETH.balanceOf(strategyContract.address)).to.equal(0);
    // });
    // TODO: test supply/borrow for WETH
  });
});
