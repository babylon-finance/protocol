const { expect } = require('chai');
const { ethers } = require('hardhat');

const addresses = require('../lib/addresses');
const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require('../lib/system.js');
const { parse, from } = require('./utils/test-helpers');
const { setupTests } = require('./fixtures/GardenFixture');

const tokens = [
  {
    name: 'YFI',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.YFI,
    value: parse('0.055723370908226538'),
  },
  {
    name: 'WBTC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.WBTC,
    value: parse('0.071420821063921639'),
  },
  {
    name: 'DAI',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.DAI,
    value: parse('3939.015400039136715572'),
  },
  {
    name: 'USDC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.USDC,
    value: parse('3959.165150489900928464'),
  },
  {
    name: 'USDT',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.USDT,
    value: parse('3972.251321495927553985'),
  },
  {
    name: 'USDT inverse',
    tokenIn: addresses.tokens.USDT,
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000251746407531788'),
  },
  {
    name: 'DAI inverse',
    tokenIn: addresses.tokens.DAI,
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000253870548459918'),
  },
];

describe('PriceOracle', function () {
  let priceOracle;
  let univ2;
  let univ3;
  let owner;

  beforeEach(async () => {
    ({ priceOracle, owner, univ2 } = await setupTests()());
    univ3 = await ethers.getContractAt('UniswapTWAP', (await priceOracle.getAdapters())[0]);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await priceOracle.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe('UniswapAnchoredView', function () {
    it('should get the price of ETH/DAI', async function () {
      const price = await priceOracle.connect(owner).getPrice(addresses.tokens.WETH, addresses.tokens.DAI);
      expect(price).to.be.gt(ethers.utils.parseEther('2000'));
    });

    it('should get the price of DAI/USDC', async function () {
      const price = await priceOracle.connect(owner).getPrice(addresses.tokens.DAI, addresses.tokens.USDC);
      expect(price).to.be.lt(ethers.utils.parseEther('1.1'));
    });
    it('should get the price of WETH/USDC', async function () {
      const price = await priceOracle.connect(owner).getPrice(addresses.tokens.WETH, addresses.tokens.USDC);
      expect(price).to.be.gt(ethers.utils.parseEther('2000'));
    });
  });

  describe('Uniswap TWAP V2', function () {
    it('should not get the price of YFI without enough observations', async function () {
      await univ2.update(addresses.tokens.YFI, addresses.tokens.WETH);
      await expect(univ2.getPrice(addresses.tokens.YFI, addresses.tokens.WETH)).to.be.reverted;
    });

    it('should get the price of YFI with enough observations', async function () {
      for (let i = 0; i < TWAP_ORACLE_GRANULARITY; i += 1) {
        await univ2.update(addresses.tokens.YFI, addresses.tokens.WETH);
        ethers.provider.send('evm_increaseTime', [TWAP_ORACLE_WINDOW / TWAP_ORACLE_GRANULARITY]);
      }
      const { amountOut } = await univ2.getPrice(addresses.tokens.YFI, addresses.tokens.WETH);
      expect(amountOut).to.be.gt(ethers.utils.parseEther('15'));
    });

    it('should get the price of DAI', async function () {
      for (let i = 0; i < TWAP_ORACLE_GRANULARITY; i += 1) {
        await univ2.update(addresses.tokens.WETH, addresses.tokens.DAI);
        ethers.provider.send('evm_increaseTime', [TWAP_ORACLE_WINDOW / TWAP_ORACLE_GRANULARITY]);
      }
      const { amountOut } = await univ2.getPrice(addresses.tokens.WETH, addresses.tokens.DAI);
      expect(amountOut).to.be.gt(ethers.utils.parseEther('500'));
    });
  });

  describe('Uniswap TWAP V3', function () {
    tokens.forEach(({ name, tokenIn, tokenOut, value }) => {
      it(`should get the price of ${name}`, async function () {
        const { amountOut } = await univ3.getPrice(tokenIn, tokenOut);
        expect(amountOut).to.be.eq(value);
      });
    });
  });

  describe('Price Oracle', function () {
    tokens.forEach(({ name, tokenIn, tokenOut, value }) => {
      it(`should get the price of ${name}`, async function () {
        const price = await priceOracle.connect(owner).getPrice(tokenIn, tokenOut);
        expect(price).to.be.closeTo(value, value.div(50));
      });
    });
  });
});
