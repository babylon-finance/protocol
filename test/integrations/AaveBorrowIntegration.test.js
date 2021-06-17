const { expect } = require('chai');
const { ethers } = require('hardhat');
const {
  createStrategy,
  executeStrategy,
  finalizeStrategy,
  DEFAULT_STRATEGY_PARAMS,
  USDC_STRATEGY_PARAMS,
  DAI_STRATEGY_PARAMS,
  WBTC_STRATEGY_PARAMS,
} = require('../fixtures/StrategyHelper');
const { ADDRESS_ZERO, ONE_ETH, STRATEGY_EXECUTE_MAP } = require('../../lib/constants');
const { from, eth } = require('../../lib/helpers');
const { setupTests } = require('../fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('../fixtures/GardenHelper');
const addresses = require('../../lib/addresses');
const { getAssetWhale } = require('../../lib/whale.js');
const { impersonateAddress } = require('../../lib/rpc');

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

  async function supplyBorrowStrategy(asset1, asset2, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    const gardenReserveAsset = await ethers.getContractAt('IERC20', token);
    await depositFunds(token, garden);

    const strategyContract = await createStrategy(
      'borrow',
      'vote',
      [signer1, signer2, signer3],
      [aaveLendIntegration.address, aaveBorrowIntegration.address],
      garden,
      false,
      [asset1.address, asset2.address],
    );

    await executeStrategy(strategyContract, { amount: STRATEGY_EXECUTE_MAP[token] });

    expect(await asset1.balanceOf(strategyContract.address)).to.equal(0);
    expect(await asset2.balanceOf(strategyContract.address)).to.be.gt(0);
    const collateral = await aaveBorrowIntegration.getCollateralBalance(strategyContract.address, asset1.address);
    expect(await aaveBorrowIntegration.getBorrowBalance(strategyContract.address, asset2.address)).to.be.gt(0);
    const beforeExitingWeth = await gardenReserveAsset.balanceOf(garden.address);
    await finalizeStrategy(strategyContract);
    expect(await asset2.balanceOf(strategyContract.address)).to.equal(0);
    expect(await asset1.balanceOf(strategyContract.address)).to.equal(0);
    expect(await gardenReserveAsset.balanceOf(garden.address)).to.gt(beforeExitingWeth);
  }
  async function supplyBorrowStrategyNAV(asset1, asset2, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    const gardenReserveAsset = await ethers.getContractAt('IERC20', token);
    await depositFunds(token, garden);

    const strategyContract = await createStrategy(
      'borrow',
      'vote',
      [signer1, signer2, signer3],
      [aaveLendIntegration.address, aaveBorrowIntegration.address],
      garden,
      false,
      [asset1.address, asset2.address],
    );

    await executeStrategy(strategyContract, { amount: STRATEGY_EXECUTE_MAP[token] });
    return strategyContract;
  }

  async function trySupplyBorrowStrategy(asset1, asset2, token, errorcode) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    const gardenReserveAsset = await ethers.getContractAt('IERC20', token);
    await depositFunds(token, garden);
    const strategyContract = await createStrategy(
      'borrow',
      'vote',
      [signer1, signer2, signer3],
      [aaveLendIntegration.address, aaveBorrowIntegration.address],
      garden,
      false,
      [asset1.address, asset2.address],
    );
    await expect(executeStrategy(strategyContract, { amount: STRATEGY_EXECUTE_MAP[token] })).to.be.revertedWith(
      errorcode,
    );
  }

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

  describe('gets NAV', function () {
    it(`gets NAV of a borrow/lend strategy at WETH Garden`, async function () {
      const garden = await createGarden({ WETH });
      const strategyContract = await createStrategy(
        'borrow',
        'vote',
        [signer1, signer2, signer3],
        [aaveLendIntegration.address, aaveBorrowIntegration.address],
        garden,
        DEFAULT_STRATEGY_PARAMS,
        [DAI.address, USDC.address],
      );

      await executeStrategy(strategyContract);
      const nav = await strategyContract.getNAV();
      expect(nav).to.be.closeTo(
        ethers.utils.parseEther('1').sub(ethers.utils.parseEther('1').mul(3).div(10)),
        ethers.utils.parseEther('1').div(10),
      );
    });
  });

  describe('Aave Borrow', function () {
    [
      { token: addresses.tokens.WETH, name: 'WETH' },
      { token: addresses.tokens.DAI, name: 'DAI' },
      { token: addresses.tokens.USDC, name: 'USDC' },
      { token: addresses.tokens.WBTC, name: 'WBTC' },
    ].forEach(({ token, name }) => {
      it(`gets NAV of a borrow/lend strategy at ${name} garden`, async function () {
        const strategyContract = await supplyBorrowStrategyNAV(DAI, WETH, token);
        // TODO Check DAI-USDC in USDC Garden gets nav 0
        const nav = await strategyContract.getNAV();
        expect(nav).to.be.gt(0);
      });
      it(`can supply DAI and borrow USDC in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(DAI, USDC, token);
      });
      it(`can supply USDC and borrow DAI in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(USDC, DAI, token);
      });
      it(`can supply WETH and borrow DAI in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(WETH, DAI, token);
      });
      it(`should fail trying to supply DAI and borrow DAI in a ${name} Garden`, async function () {
        await trySupplyBorrowStrategy(DAI, DAI, token, 'revert 13');
      });
      it(`should fail trying to supply WETH and borrow WETH in a ${name} Garden`, async function () {
        await trySupplyBorrowStrategy(WETH, WETH, token, 'revert 13');
      });
      it(`should fail trying to supply USDC and borrow USDC in a ${name} Garden`, async function () {
        // TODO Check why Aave reverts 1 before reverting by 13
        await trySupplyBorrowStrategy(USDC, USDC, token, 'revert 1');
      });
    });
  });
});
