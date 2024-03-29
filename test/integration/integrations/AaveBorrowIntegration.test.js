const { expect } = require('chai');
const { ethers } = require('hardhat');
const {
  createStrategy,
  executeStrategy,
  finalizeStrategy,
  DEFAULT_STRATEGY_PARAMS,
} = require('fixtures/StrategyHelper');
const { STRATEGY_EXECUTE_MAP, GARDENS } = require('lib/constants');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const {
  pick,
  increaseTime,
  normalizeDecimals,
  getERC20,
  getContract,
  parse,
  from,
  eth,
} = require('utils/test-helpers');

describe('AaveBorrowIntegrationTest', function () {
  let aaveBorrowIntegration;
  let aaveLendIntegration;
  let signer1;
  let signer2;
  let signer3;
  let USDC;
  let DAI;
  let WETH;

  async function supplyBorrowStrategy(asset1, asset2, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    const gardenReserveAsset = await getERC20(token);
    await depositFunds(token, garden);

    const strategyContract = await createStrategy(
      'borrow',
      'vote',
      [signer1, signer2, signer3],
      [aaveLendIntegration.address, aaveBorrowIntegration.address],
      garden,
      false,
      [asset1.address, 0, asset2.address, 0],
    );

    let amount = STRATEGY_EXECUTE_MAP[token];
    await executeStrategy(strategyContract, { amount });
    // Check NAV
    expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(50));

    expect(await asset1.balanceOf(strategyContract.address)).to.equal(0);
    expect(await asset2.balanceOf(strategyContract.address)).to.be.gt(0);
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
    await depositFunds(token, garden);

    const strategyContract = await createStrategy(
      'borrow',
      'vote',
      [signer1, signer2, signer3],
      [aaveLendIntegration.address, aaveBorrowIntegration.address],
      garden,
      false,
      [asset1.address, 0, asset2.address, 0],
    );

    await executeStrategy(strategyContract, { amount: STRATEGY_EXECUTE_MAP[token] });
    return strategyContract;
  }

  async function trySupplyBorrowStrategy(asset1, asset2, token, errorcode) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    await depositFunds(token, garden);
    const strategyContract = await createStrategy(
      'borrow',
      'vote',
      [signer1, signer2, signer3],
      [aaveLendIntegration.address, aaveBorrowIntegration.address],
      garden,
      false,
      [asset1.address, 0, asset2.address, 0],
    );
    await expect(executeStrategy(strategyContract, { amount: STRATEGY_EXECUTE_MAP[token] })).to.be.revertedWith(
      errorcode,
    );
  }

  beforeEach(async () => {
    ({ aaveLendIntegration, aaveBorrowIntegration, signer1, signer2, signer3 } = await setupTests()());
    USDC = await getERC20(addresses.tokens.USDC);
    DAI = await getERC20(addresses.tokens.DAI);
    WETH = await getERC20(addresses.tokens.WETH);
  });

  describe('gets NAV', function () {
    it(`gets NAV of a borrow/lend strategy at WETH Garden`, async function () {
      const garden = await createGarden({});
      const strategyContract = await createStrategy(
        'borrow',
        'vote',
        [signer1, signer2, signer3],
        [aaveLendIntegration.address, aaveBorrowIntegration.address],
        garden,
        DEFAULT_STRATEGY_PARAMS,
        [DAI.address, 0, USDC.address, 0],
      );
      await executeStrategy(strategyContract);

      const nav = await strategyContract.getNAV();
      expect(nav).to.be.closeTo(eth('1'), eth('1').div(10));
    });
  });

  describe('Aave Borrow', function () {
    it(`should fail trying to supply DAI and borrow DAI at Aave  in a WETH Garden`, async function () {
      await trySupplyBorrowStrategy(DAI, DAI, addresses.tokens.WETH, 'There is no collateral locked');
    });

    pick(GARDENS.slice(0, 3)).forEach(({ token, name }) => {
      it(`gets NAV of a borrow/lend strategy at ${name} garden`, async function () {
        const strategyContract = await supplyBorrowStrategyNAV(DAI, WETH, token);
        const nav = await strategyContract.getNAV();
        expect(nav).to.be.gt(0);
      });
      it(`can supply DAI and borrow USDC at Aave in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(DAI, USDC, token);
      });
      it(`can supply USDC and borrow DAI at Aave in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(USDC, DAI, token);
      });
      it(`can supply WETH and borrow DAI at Aave  in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(WETH, DAI, token);
      });
    });
  });
});
