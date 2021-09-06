const { expect } = require('chai');

const addresses = require('lib/addresses');
const { from, parse } = require('lib/helpers');
const { setupTests } = require('fixtures/GardenFixture');

const tokens = [
  {
    name: 'WETH->renBTC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.renBTC,
    value: from('60999016686834644'),
  },
  {
    name: 'WETH->CRV',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.CRV,
    value: parse('1401'),
  },
  {
    name: 'WETH->rETH',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.rETH,
    value: from('1000493000000000000'),
  },
  {
    name: 'WETH->sAAVE',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.sAAVE,
    value: from('7105665770955090427'),
  },
  {
    name: 'DAI->sAAVE',
    tokenIn: addresses.tokens.DAI,
    tokenOut: addresses.tokens.sAAVE,
    value: from('3085633658574974'),
  },
  {
    name: 'DAI->USDC',
    tokenIn: addresses.tokens.DAI,
    tokenOut: addresses.tokens.USDC,
    value: from('1000493000000000000'),
  },
  {
    name: 'DAI->USDT',
    tokenIn: addresses.tokens.DAI,
    tokenOut: addresses.tokens.USDT,
    value: from('1000493000000000000'),
  },
  {
    name: 'WETH->TUSD',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.TUSD,
    value: parse('2413.355851430197330006'),
  },
  {
    name: 'TUSD->WETH',
    tokenIn: addresses.tokens.TUSD,
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000414029352230162'),
  },
  {
    name: 'YFI->DAI',
    tokenIn: addresses.tokens.YFI,
    tokenOut: addresses.tokens.DAI,
    value: from('31551677607351281515736'),
  },
  {
    name: 'SNX->USDT',
    tokenIn: addresses.tokens.SNX,
    tokenOut: addresses.tokens.USDT,
    value: from('9980228224525781396'),
  },
  {
    name: 'WBTC->DAI',
    tokenIn: addresses.tokens.WBTC,
    tokenOut: addresses.tokens.DAI,
    value: from('38038676239828669947037'),
  },
  {
    name: 'COMP->USDC',
    tokenIn: addresses.tokens.COMP,
    tokenOut: addresses.tokens.USDC,
    value: from('362566529993303469131'),
  },
  {
    name: 'YFI',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.YFI,
    value: parse('0.069622579431591801'),
  },
  {
    name: 'WBTC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.WBTC,
    value: parse('0.060340821063921639'),
  },
  {
    name: 'DAI',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.DAI,
    value: parse('2334.872681753296279996'),
  },
  {
    name: 'USDC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.USDC,
    value: parse('2336.981086483790897275'),
  },
  {
    name: 'USDT',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.USDT,
    value: parse('2332.630550000000000000'),
  },
  {
    name: 'USDT inverse',
    tokenIn: addresses.tokens.USDT,
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000426868407531788'),
  },
  {
    name: 'DAI inverse',
    tokenIn: addresses.tokens.DAI,
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000426684548459918'),
  },
  {
    name: 'CRV 3 Pool',
    tokenIn: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
    tokenOut: addresses.tokens.DAI,
    value: parse('1.0'),
  },
  {
    name: 'CRV 3 Pool Inverse',
    tokenIn: addresses.tokens.DAI,
    tokenOut: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
    value: parse('0.97'),
  },
  {
    name: 'WBTC to renBTC',
    tokenIn: addresses.tokens.WBTC,
    tokenOut: addresses.tokens.renBTC,
    value: parse('0.996'),
  },
  {
    name: 'CRV 3 Pool',
    tokenIn: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
    tokenOut: addresses.tokens.DAI,
    value: parse('1.0'),
  },
  {
    name: 'CRV 3 Pool Inverse',
    tokenIn: addresses.tokens.DAI,
    tokenOut: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
    value: parse('0.97'),
  },
  {
    name: 'WBTC to renBTC',
    tokenIn: addresses.tokens.WBTC,
    tokenOut: addresses.tokens.renBTC,
    value: parse('0.996'),
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

    addresses.aave.atokens.slice(0, 5).forEach(({ atoken, token }) => {
      it(`should get the price of atokens ${atoken}`, async function () {
        const price = await priceOracle.connect(owner).getPrice(atoken, addresses.tokens.DAI);
        const priceUnderlying = await priceOracle.connect(owner).getPrice(token, addresses.tokens.DAI);
        expect(price).to.be.equal(priceUnderlying);
      });
    });

    addresses.cream.crtokens.slice(0, 5).forEach(({ ctoken, token }) => {
      it(`should get the price of crtokens ${ctoken}`, async function () {
        const price = await priceOracle.connect(owner).getPrice(ctoken, addresses.tokens.DAI);
        const priceUnderlying = await priceOracle.connect(owner).getPrice(token, addresses.tokens.DAI);
        const exchangeRate = await priceOracle.getCreamExchangeRate(ctoken);
        expect(price).to.be.equal(
          priceUnderlying
            .mul(exchangeRate)
            .div(10 ** 10)
            .div(10 ** 8),
        );
      });
    });

    addresses.synthetix.synths.slice(0, 5).forEach(({ synth, token }) => {
      it(`should get the price of synthetix ${synth}`, async function () {
        const price = await priceOracle.connect(owner).getPrice(synth, addresses.tokens.DAI);
        expect(price).to.be.gt(0);
        if (token) {
          const priceUnderlying = await priceOracle.connect(owner).getPrice(token, addresses.tokens.DAI);
          expect(price).to.be.closeTo(priceUnderlying, ethers.utils.parseEther('0.01'));
        }
      });
    });
  });
});
