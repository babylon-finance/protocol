const { expect } = require('chai');
const { ethers } = require('hardhat');
const {
  createStrategy,
  executeStrategy,
  finalizeStrategy,
  DEFAULT_STRATEGY_PARAMS,
} = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { ADDRESS_ZERO, STRATEGY_EXECUTE_MAP } = require('lib/constants');
const { increaseTime, normalizeDecimals, getERC20, getContract, parse, from, eth } = require('utils/test-helpers');

describe('CompoundBorrowIntegrationTest', function () {
  let compoundBorrowIntegration;
  let compoundLendIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let USDC;
  let DAI;
  let WETH;
  let WBTC;

  async function supplyBorrowStrategy(asset1, asset2, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    const gardenReserveAsset = await getERC20(token);
    await depositFunds(token, garden);

    const asset1Address = asset1.address === addresses.tokens.WETH ? ADDRESS_ZERO : asset1.address;
    const asset2Address = asset2.address === addresses.tokens.WETH ? ADDRESS_ZERO : asset2.address;

    const strategyContract = await createStrategy(
      'borrow',
      'vote',
      [signer1, signer2, signer3],
      [compoundLendIntegration.address, compoundBorrowIntegration.address],
      garden,
      false,
      [asset1Address, 0, asset2Address, 0],
    );
    const amount = STRATEGY_EXECUTE_MAP[token];
    await executeStrategy(strategyContract, { amount });
    // Check NAV
    expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(50));

    expect(await asset1.balanceOf(strategyContract.address)).to.equal(0);
    expect(await asset2.balanceOf(strategyContract.address)).to.be.gt(0);

    expect(await compoundBorrowIntegration.getBorrowBalance(strategyContract.address, asset2.address)).to.be.gt(0);
    const balanceBeforeExiting = await gardenReserveAsset.balanceOf(garden.address);
    await finalizeStrategy(strategyContract);

    expect(await asset2.balanceOf(strategyContract.address)).to.equal(0);
    expect(await asset1.balanceOf(strategyContract.address)).to.equal(0);

    expect(await gardenReserveAsset.balanceOf(garden.address)).to.gt(balanceBeforeExiting);
  }

  async function trySupplyBorrowStrategy(asset1, asset2, token, errorcode) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    await depositFunds(token, garden);

    const asset1Address = asset1.address === addresses.tokens.WETH ? ADDRESS_ZERO : asset1.address;
    const asset2Address = asset2.address === addresses.tokens.WETH ? ADDRESS_ZERO : asset2.address;

    const strategyContract = await createStrategy(
      'borrow',
      'vote',
      [signer1, signer2, signer3],
      [compoundLendIntegration.address, compoundBorrowIntegration.address],
      garden,
      false,
      [asset1Address, 0, asset2Address, 0],
    );
    await expect(executeStrategy(strategyContract, { amount: STRATEGY_EXECUTE_MAP[token] })).to.be.revertedWith(
      errorcode,
    );
  }

  beforeEach(async () => {
    ({ garden1, compoundLendIntegration, compoundBorrowIntegration, signer1, signer2, signer3 } = await setupTests()());
    USDC = await getERC20(addresses.tokens.USDC);
    DAI = await getERC20(addresses.tokens.DAI);
    WETH = await getERC20(addresses.tokens.WETH);
    WBTC = await getERC20(addresses.tokens.WBTC);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const lendDeployed = await compoundBorrowIntegration.deployed();
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
        [DAI.address, 0, USDC.address, 0],
      );

      await executeStrategy(strategyContract);

      expect(await DAI.balanceOf(strategyContract.address)).to.equal(0);
      expect(await USDC.balanceOf(strategyContract.address)).to.be.gt(0);
      const collateral = await compoundBorrowIntegration.getCollateralBalance(strategyContract.address, DAI.address);
      expect(collateral).to.be.gt(ethers.utils.parseEther('1931'));
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
        [USDC.address, 0, DAI.address, 0],
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

    it('can supply WETH and borrow DAI in a WETH Garden', async function () {
      const strategyContract = await createStrategy(
        'borrow',
        'vote',
        [signer1, signer2, signer3],
        [compoundLendIntegration.address, compoundBorrowIntegration.address],
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [ADDRESS_ZERO, 0, DAI.address, 0], // eth, dai
      );

      await executeStrategy(strategyContract);
      expect(await WETH.balanceOf(strategyContract.address)).to.equal(0);
      expect(await DAI.balanceOf(strategyContract.address)).to.be.gt(0);
      const collateral = await compoundBorrowIntegration.getCollateralBalance(strategyContract.address, ADDRESS_ZERO);
      expect(collateral).to.be.closeTo(ethers.utils.parseEther('1'), ethers.utils.parseEther('1').div(100));
      expect(await compoundBorrowIntegration.getBorrowBalance(strategyContract.address, DAI.address)).to.be.gt(
        ethers.utils.parseEther('578'),
      );
      const beforeExitingWeth = await WETH.balanceOf(garden1.address);
      await finalizeStrategy(strategyContract);
      expect(await DAI.balanceOf(strategyContract.address)).to.equal(0);
      expect(await WETH.balanceOf(strategyContract.address)).to.equal(0);
      expect(await WETH.balanceOf(garden1.address)).to.gt(beforeExitingWeth);
    });

    it('can supply DAI and borrow ETH in a WETH Garden', async function () {
      const strategyContract = await createStrategy(
        'borrow',
        'vote',
        [signer1, signer2, signer3],
        [compoundLendIntegration.address, compoundBorrowIntegration.address],
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [DAI.address, 0, ADDRESS_ZERO, 0],
      );

      await executeStrategy(strategyContract);
      expect(await DAI.balanceOf(strategyContract.address)).to.equal(0);
      const collateral = await compoundBorrowIntegration.getCollateralBalance(strategyContract.address, DAI.address);
      expect(collateral).to.be.gt(ethers.utils.parseEther('1930'));
      expect(await compoundBorrowIntegration.getBorrowBalance(strategyContract.address, ADDRESS_ZERO)).to.be.gt(0);
      const beforeExitingWeth = await WETH.balanceOf(garden1.address);
      await finalizeStrategy(strategyContract);
      expect(await DAI.balanceOf(strategyContract.address)).to.equal(0);
      expect(await WETH.balanceOf(garden1.address)).to.gt(beforeExitingWeth);
    });
  });
  describe('Compound Borrow Multigarden multiasset', function () {
    [
      { token: addresses.tokens.WETH, name: 'WETH' },
      { token: addresses.tokens.DAI, name: 'DAI' },
      { token: addresses.tokens.USDC, name: 'USDC' },
      { token: addresses.tokens.WBTC, name: 'WBTC' },
    ].forEach(({ token, name }) => {
      it(`can supply DAI and borrow USDC at Compound in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(DAI, USDC, token);
      });
      it(`can supply WBTC and borrow DAI at Compound in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(WBTC, DAI, token);
      });
      it(`can supply USDC and borrow DAI at Compound in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(USDC, DAI, token);
      });
      it(`can supply WETH and borrow DAI at Compound in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(WETH, DAI, token);
      });
      it(`should fail trying to supply DAI and borrow DAI at Compound in a ${name} Garden`, async function () {
        await trySupplyBorrowStrategy(DAI, DAI, token, 'There is no collateral locked');
      });
      it(`should fail trying to supply WETH and borrow WETH at Compound in a ${name} Garden`, async function () {
        await trySupplyBorrowStrategy(WETH, WETH, token, 'There is no collateral locked');
      });
      it(`should fail trying to supply USDC and borrow USDC at Compound in a ${name} Garden`, async function () {
        await trySupplyBorrowStrategy(USDC, USDC, token, 'There is no collateral locked');
      });
    });
  });
});
