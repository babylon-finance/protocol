const { expect } = require('chai');
const {
  createStrategy,
  executeStrategy,
  finalizeStrategy,
  DEFAULT_STRATEGY_PARAMS,
} = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { GARDENS, ADDRESS_ZERO, STRATEGY_EXECUTE_MAP } = require('lib/constants');
const { pick, getERC20, eth } = require('utils/test-helpers');

describe('FuseBorrowIntegrationTest', function () {
  let fuseBorrowIntegration;
  let fuseLendIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let FRAX;
  let FEI;
  let DAI;
  let BABL;

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
      [fuseLendIntegration.address, fuseBorrowIntegration.address],
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

    expect(await fuseBorrowIntegration.getBorrowBalance(strategyContract.address, asset2.address)).to.be.gt(0);
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
      [fuseLendIntegration.address, fuseBorrowIntegration.address],
      garden,
      false,
      [asset1Address, 0, asset2Address, 0],
    );
    await expect(executeStrategy(strategyContract, { amount: STRATEGY_EXECUTE_MAP[token] })).to.be.revertedWith(
      errorcode,
    );
  }

  beforeEach(async () => {
    ({ garden1, fuseLendIntegration, fuseBorrowIntegration, signer1, signer2, signer3 } = await setupTests()());
    FRAX = await getERC20(addresses.tokens.FRAX);
    FEI = await getERC20(addresses.tokens.FEI);
    DAI = await getERC20(addresses.tokens.DAI);
    BABL = await getERC20(addresses.tokens.BABL);
  });

  describe('Fuse Borrow Multigarden multiasset', function () {
    pick(GARDENS).forEach(({ token, name }) => {
      it(`can supply DAI and borrow FRAX at Fuse in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(DAI, FRAX, token);
      });
      it(`can supply FEI and borrow BABL at Fuse in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(FEI, BABL, token);
      });
      it(`can supply DAI and borrow BABL at Fuse in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(DAI, BABL, token);
      });
      it(`can supply DAI and borrow ETH at Fuse in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(DAI, ADDRESS_ZERO, token);
      });
      it(`can supply ETH and borrow DAI at Fuse in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(ADDRESS_ZERO, DAI, token);
      });
      it(`should fail trying to supply DAI and borrow DAI at Fuse in a ${name} Garden`, async function () {
        await trySupplyBorrowStrategy(DAI, DAI, token, 'There is no collateral locked');
      });
      it(`should fail trying to supply ETH and borrow ETH at Fuse in a ${name} Garden`, async function () {
        await trySupplyBorrowStrategy(ADDRESS_ZERO, ADDRESS_ZERO, token, 'There is no collateral locked');
      });
      it(`should fail trying to supply BABL and borrow BABL at Fuse in a ${name} Garden`, async function () {
        await trySupplyBorrowStrategy(BABL, BABL, token, 'There is no collateral locked');
      });
    });
  });
});
