const { expect } = require('chai');

const addresses = require('../lib/addresses');
const { from, parse } = require('../lib/helpers');
const { setupTests } = require('./fixtures/GardenFixture');

const tokens = [
  {
    name: 'YFI->DAI',
    tokenIn: addresses.tokens.YFI,
    tokenOut: addresses.tokens.DAI,
    value: from('70688749367415192058580'),
  },
  {
    name: 'SNX->USDT',
    tokenIn: addresses.tokens.SNX,
    tokenOut: addresses.tokens.USDT,
    value: from('16644203924869776128'),
  },
  {
    name: 'WBTC->DAI',
    tokenIn: addresses.tokens.WBTC,
    tokenOut: addresses.tokens.DAI,
    value: from('55152199895793998496139'),
  },
  {
    name: 'COMP->USDC',
    tokenIn: addresses.tokens.COMP,
    tokenOut: addresses.tokens.USDC,
    value: from('794147161556756252270'),
  },
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
  let owner;

  beforeEach(async () => {
    ({ priceOracle, owner } = await setupTests()());
  });

  describe('Price Oracle', function () {
    tokens.forEach(({ name, tokenIn, tokenOut, value }) => {
      it(`should get the price of ${name}`, async function () {
        const price = await priceOracle.connect(owner).getPrice(tokenIn, tokenOut);
        expect(price).to.be.closeTo(value, value.div(50));
      });
    });

    addresses.compound.ctokens.forEach(({ ctoken, token }) => {
      it(`should get the price of ctokens ${ctoken}`, async function () {
        const price = await priceOracle.connect(owner).getPrice(ctoken, addresses.tokens.DAI);
        const priceUnderlying = await priceOracle.connect(owner).getPrice(token, addresses.tokens.DAI);
        const exchangeRate = await priceOracle.getCompoundExchangeRate(ctoken);
        expect(price).to.be.equal(
          priceUnderlying
            .mul(exchangeRate)
            .div(10 ** 10)
            .div(10 ** 8),
        );
      });

      it(`should get the price of inverse ctokens ${ctoken}`, async function () {
        const price = await priceOracle.connect(owner).getPrice(addresses.tokens.DAI, ctoken);
        const priceUnderlying = await priceOracle.connect(owner).getPrice(addresses.tokens.DAI, token);
        const exchangeRate = await priceOracle.getCompoundExchangeRate(ctoken);
        expect(price).to.be.equal(
          priceUnderlying
            .mul(10 ** 10)
            .mul(10 ** 8)
            .div(exchangeRate),
        );
      });
    });

    addresses.aave.atokens.forEach(({ atoken, token }) => {
      it(`should get the price of atokens ${atoken}`, async function () {
        const price = await priceOracle.connect(owner).getPrice(atoken, addresses.tokens.DAI);
        const priceUnderlying = await priceOracle.connect(owner).getPrice(token, addresses.tokens.DAI);
        expect(price).to.be.equal(priceUnderlying);
      });
    });

    addresses.cream.crtokens.forEach(({ crtoken, token }) => {
      it(`should get the price of crtokens ${crtoken}`, async function () {
        const price = await priceOracle.connect(owner).getPrice(crtoken, addresses.tokens.DAI);
        const priceUnderlying = await priceOracle.connect(owner).getPrice(token, addresses.tokens.DAI);
        const exchangeRate = await priceOracle.getCreamExchangeRate(crtoken);
        console.log(ethers.utils.formatEther(price));
        console.log(ethers.utils.formatEther(priceUnderlying));
        expect(price).to.be.equal(
          priceUnderlying
            .mul(exchangeRate)
            .div(10 ** 10)
            .div(10 ** 8),
        );
      });
    });
  });
});
