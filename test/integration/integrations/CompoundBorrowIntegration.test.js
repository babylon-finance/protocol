const { expect } = require('chai');
const { createStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { GARDENS, ADDRESS_ZERO, STRATEGY_EXECUTE_MAP } = require('lib/constants');
const { pick, getERC20 } = require('utils/test-helpers');

describe('CompoundBorrowIntegrationTest', function () {
  let compoundBorrowIntegration;
  let compoundLendIntegration;
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
    expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(20));

    expect(await asset1.balanceOf(strategyContract.address)).to.equal(0);
    expect(await asset2.balanceOf(strategyContract.address)).to.be.gt(0);

    expect(await compoundBorrowIntegration.getBorrowBalance(strategyContract.address, asset2Address)).to.be.gt(0);
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
    ({ compoundLendIntegration, compoundBorrowIntegration, signer1, signer2, signer3 } = await setupTests()());
    USDC = await getERC20(addresses.tokens.USDC);
    DAI = await getERC20(addresses.tokens.DAI);
    WETH = await getERC20(addresses.tokens.WETH);
    WBTC = await getERC20(addresses.tokens.WBTC);
  });

  describe('Compound Borrow Multigarden multiasset', function () {
    it(`should fail trying to supply DAI and borrow DAI at Compound in a WETH Garden`, async function () {
      await trySupplyBorrowStrategy(DAI, DAI, addresses.tokens.WETH, 'There is no collateral locked');
    });

    pick(GARDENS.slice(0, 3)).forEach(({ token, name }) => {
      it(`can supply DAI and borrow USDC at Compound in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(DAI, USDC, token);
      });

      it(`can supply WBTC and borrow DAI at Compound in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(WBTC, DAI, token);
      });

      it(`can supply USDC and borrow DAI at Compound in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(USDC, DAI, token);
      });

      it(`can supply DAI and borrow ETH at Compound in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(DAI, WETH, token);
      });

      it(`can supply WETH and borrow DAI at Compound in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(WETH, DAI, token);
      });
    });
  });
});
