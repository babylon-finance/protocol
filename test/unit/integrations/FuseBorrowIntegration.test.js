const { expect } = require('chai');
const { createStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { GARDENS, ADDRESS_ZERO, STRATEGY_EXECUTE_MAP } = require('lib/constants');
const { pick, getERC20, eth, increaseTime } = require('utils/test-helpers');

describe('FuseBorrowIntegrationTest', function () {
  let fuseBorrowIntegration;
  let fuseLendIntegration;
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let FRAX;
  let WETH;
  let FEI;
  let DAI;
  let BABL;
  let cDAI;
  let cWETH;
  let cFRAX;
  let cFEI;
  let cBABL;

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
    const amount = STRATEGY_EXECUTE_MAP[token].mul(7);
    await executeStrategy(strategyContract, { amount });
    // Check NAV
    expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(30));
    if (asset1.address === WETH.address) {
      expect(await ethers.provider.getBalance(strategyContract.address)).to.equal(0);
    } else {
      expect(await asset1.balanceOf(strategyContract.address)).to.equal(0);
    }
    if (asset2.address === WETH.address) {
      expect(await ethers.provider.getBalance(strategyContract.address)).to.be.gt(0);
    } else {
      expect(await asset2.balanceOf(strategyContract.address)).to.be.gt(0);
    }
    expect(await fuseBorrowIntegration.getBorrowBalance(strategyContract.address, asset2Address)).to.be.gt(0);

    const balanceBeforeExiting = await gardenReserveAsset.balanceOf(garden.address);
    await finalizeStrategy(strategyContract);

    if (asset2.address === WETH.address) {
      expect(await ethers.provider.getBalance(strategyContract.address)).to.equal(0);
    } else {
      expect(await asset2.balanceOf(strategyContract.address)).to.equal(0);
    }

    if (asset1.address === WETH.address) {
      expect(await ethers.provider.getBalance(strategyContract.address)).to.equal(0);
    } else {
      expect(await asset1.balanceOf(strategyContract.address)).to.equal(0);
    }

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
    ({ fuseLendIntegration, fuseBorrowIntegration, signer1, signer2, signer3, owner } = await setupTests()());
    FRAX = await getERC20(addresses.tokens.FRAX);
    WETH = await getERC20(addresses.tokens.WETH);
    FEI = await getERC20(addresses.tokens.FEI);
    DAI = await getERC20(addresses.tokens.DAI);
    BABL = await getERC20(addresses.tokens.BABL);
    cDAI = await ethers.getContractAt('ICToken', '0xa6c25548df506d84afd237225b5b34f2feb1aa07');
    cWETH = await ethers.getContractAt('ICEther', '0x7dbc3af9251756561ce755fcc11c754184af71f7');
    cBABL = await ethers.getContractAt('ICToken', '0x812eedc9eba9c428434fd3ce56156b4e23012ebc');
    cFRAX = await ethers.getContractAt('ICToken', '0xa54c548d11792b3d26ad74f5f899e12cdfd64fd6');
    cFEI = await ethers.getContractAt('ICToken', '0x3a2804ec0ff521374af654d8d0daa1d1ae1ee900');

    // const comptroller = await ethers.getContractAt('IComptroller', '0xC7125E3A2925877C7371d579D29dAe4729Ac9033');

    // Add Liquidity to the markets
    await DAI.connect(owner).approve(cDAI.address, eth('100000'), { gasPrice: 0 });
    await cDAI.connect(owner).mint(eth('100000'), { gasPrice: 0 });
    await BABL.connect(owner).approve(cBABL.address, eth('1000'), { gasPrice: 0 });
    await cBABL.connect(owner).mint(eth('1000'), { gasPrice: 0 });
    await cWETH.connect(signer3).mint({ value: eth('5'), gasPrice: 0 });
    await FRAX.connect(owner).approve(cFRAX.address, eth('100000'), { gasPrice: 0 });
    await cFRAX.connect(owner).mint(eth('100000'), { gasPrice: 0 });
    await FEI.connect(owner).approve(cFEI.address, eth('100000'), { gasPrice: 0 });
    await cFEI.connect(owner).mint(eth('100000'), { gasPrice: 0 });
    await increaseTime(86400 * 20);
    await cFRAX.connect(owner).accrueInterest({ gasPrice: 0 });
  });

  describe('Fuse Borrow Multigarden multiasset', function () {
    pick(GARDENS.slice(0, 3)).forEach(({ token, name }) => {
      it(`can supply DAI and borrow FRAX at Fuse in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(DAI, FRAX, token);
      });
      it(`can supply BABL and borrow FEI at Fuse in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(BABL, FEI, token);
      });
      it(`can supply FRAX and borrow DAI at Fuse in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(FRAX, DAI, token);
      });
      it(`can supply FEI and borrow ETH at Fuse in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(FEI, WETH, token);
      });
      it.skip(`can supply ETH and borrow DAI at Fuse in a ${name} Garden`, async function () {
        await supplyBorrowStrategy(WETH, DAI, token);
      });
      it(`should fail trying to supply DAI and borrow DAI at Fuse in a ${name} Garden`, async function () {
        await trySupplyBorrowStrategy(DAI, DAI, token, 'There is no collateral locked');
      });
      it(`should fail trying to supply ETH and borrow ETH at Fuse in a ${name} Garden`, async function () {
        await trySupplyBorrowStrategy(WETH, WETH, token, 'There is no collateral locked');
      });
      it(`should fail trying to supply BABL and borrow BABL at Fuse in a ${name} Garden`, async function () {
        await trySupplyBorrowStrategy(BABL, BABL, token, 'There is no collateral locked');
      });
    });
  });
});
