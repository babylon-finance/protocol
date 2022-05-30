const { expect } = require('chai');
const addresses = require('lib/addresses');
const { from, parse } = require('lib/helpers');
const { pick } = require('utils/test-helpers');
const { setupTests } = require('fixtures/GardenFixture');

const tokens = [
  {
    name: 'WETH -> AAVE',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.AAVE,
    value: from('18163621779427627024'),
  },
  {
    name: 'CVX -> DAI',
    tokenIn: addresses.tokens.CVX,
    tokenOut: addresses.tokens.DAI,
    value: from('9552349665691024258'),
  },
  {
    name: 'BABL -> DAI',
    tokenIn: addresses.tokens.BABL,
    tokenOut: addresses.tokens.DAI,
    value: from('28870833417744989243'),
  },
  {
    name: 'BABL -> USDC',
    tokenIn: addresses.tokens.BABL,
    tokenOut: addresses.tokens.USDC,
    value: from('28790188298823841336'),
  },
  {
    name: 'BABL -> WETH',
    tokenIn: addresses.tokens.BABL,
    tokenOut: addresses.tokens.WETH,
    value: from('16215399307137759'),
  },
  {
    name: 'BABL -> WBTC',
    tokenIn: addresses.tokens.BABL,
    tokenOut: addresses.tokens.WBTC,
    value: from('989018134143773'),
  },
  {
    name: 'GF->DAI',
    tokenIn: '0xaaef88cea01475125522e117bfe45cf32044e238',
    tokenOut: addresses.tokens.DAI,
    value: from('444475893785321838'),
  },
  {
    name: 'FRAX->DAI',
    tokenIn: addresses.tokens.FRAX,
    tokenOut: addresses.tokens.DAI,
    value: from('999447178825784409'),
  },
  {
    name: 'WETH->wstETH',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.wstETH,
    value: from('946487750617709900'),
  },
  {
    name: 'WETH->stETH',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.stETH,
    value: from('1006074239866975462'),
  },
  {
    name: 'DPI->USDC',
    tokenIn: addresses.tokens.DPI,
    tokenOut: addresses.tokens.USDC,
    value: parse('89.531279839378735346'),
  },
  {
    name: 'CRV->LDO',
    tokenIn: addresses.tokens.CRV,
    tokenOut: '0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32',
    value: from('1152337986696638633'),
  },
  {
    name: 'USDC->DPI',
    tokenIn: addresses.tokens.USDC,
    tokenOut: addresses.tokens.DPI,
    value: parse('0.0111'),
  },
  {
    name: 'WETH-> YEARN dai',
    tokenIn: addresses.tokens.WETH,
    tokenOut: '0xdA816459F1AB5631232FE5e97a05BBBb94970c95',
    value: parse('1730.915612614859653532'),
  },
  {
    name: 'WETH-> YEARN USDC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: '0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9',
    value: parse('1619.495439740702037995'),
  },
  {
    name: 'YEARN dai-> WETH dai',
    tokenIn: '0xdA816459F1AB5631232FE5e97a05BBBb94970c95',
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000577'),
  },
  {
    name: 'YEARN USDC-> WETH dai',
    tokenIn: '0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9',
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000617'),
  },
  {
    name: 'WETH->tripool direct',
    tokenIn: addresses.tokens.WETH,
    tokenOut: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
    value: parse('1742.546655754214311685'),
  },
  {
    name: 'tripool->WETH',
    tokenIn: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000573'),
  },
  {
    name: 'WETH->tricrypto2',
    tokenIn: addresses.tokens.WETH,
    tokenOut: '0xc4AD29ba4B3c580e6D59105FFf484999997675Ff',
    value: parse('1.57'),
  },
  {
    name: 'tricrypto2->WETH',
    tokenIn: '0xc4AD29ba4B3c580e6D59105FFf484999997675Ff',
    tokenOut: addresses.tokens.WETH,
    value: parse('0.634'),
  },
  {
    name: 'WETH->renBTC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.renBTC,
    value: from('61269057437774994'),
  },
  {
    name: 'WETH->CRV',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.CRV,
    value: parse('1495.875307441108806091'),
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
    value: parse('1764.407804575983940687'),
  },
  {
    name: 'TUSD->WETH',
    tokenIn: addresses.tokens.TUSD,
    tokenOut: addresses.tokens.WETH,
    value: parse('0.0005668'),
  },
  {
    name: 'YFI->DAI',
    tokenIn: addresses.tokens.YFI,
    tokenOut: addresses.tokens.DAI,
    value: from('7834181599402921090191'),
  },
  {
    name: 'SNX->USDT',
    tokenIn: addresses.tokens.SNX,
    tokenOut: addresses.tokens.USDT,
    value: from('2397337932000098257'),
  },
  {
    name: 'WBTC->DAI',
    tokenIn: addresses.tokens.WBTC,
    tokenOut: addresses.tokens.DAI,
    value: from('28971970325193157474032'),
  },
  {
    name: 'COMP->USDC',
    tokenIn: addresses.tokens.COMP,
    tokenOut: addresses.tokens.USDC,
    value: from('58288182856284565784'),
  },
  {
    name: 'YFI',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.YFI,
    value: parse('0.2272'),
  },
  {
    name: 'WBTC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.WBTC,
    value: parse('0.0611'),
  },
  {
    name: 'WETH->DAI',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.DAI,
    value: parse('1780.277281503964185794'),
  },
  {
    name: 'USDC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.USDC,
    value: parse('1775.163851352164116664'),
  },
  {
    name: 'USDT',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.USDT,
    value: parse('1782.532489433037288362'),
  },
  {
    name: 'USDT inverse',
    tokenIn: addresses.tokens.USDT,
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000561'),
  },
  {
    name: 'DAI inverse',
    tokenIn: addresses.tokens.DAI,
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000561'),
  },
  {
    name: 'CRV 3 Pool',
    tokenIn: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
    tokenOut: addresses.tokens.DAI,
    value: parse('1.02'),
  },
  {
    name: 'CRV 3 Pool Inverse',
    tokenIn: addresses.tokens.DAI,
    tokenOut: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
    value: parse('0.981'),
  },
  {
    name: 'WBTC to renBTC',
    tokenIn: addresses.tokens.WBTC,
    tokenOut: addresses.tokens.renBTC,
    value: parse('0.996'),
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
    pick(tokens).forEach(({ name, tokenIn, tokenOut, value }) => {
      it(`should get the price of ${name}`, async function () {
        const price = await priceOracle.connect(owner).getPrice(tokenIn, tokenOut);
        expect(price).to.be.closeTo(value, value.div(50));
      });
    });

    pick(addresses.compound.ctokens.slice(0, 5)).forEach(({ ctoken, token }) => {
      it(`should get the price of ctokens ${ctoken}`, async function () {
        const price = await priceOracle.connect(owner).getPrice(ctoken, addresses.tokens.DAI);
        const priceUnderlying = await priceOracle.connect(owner).getPrice(token, addresses.tokens.DAI);
        const exchangeRate = await priceOracle.getCompoundExchangeRate(ctoken, token);
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
        const exchangeRate = await priceOracle.getCompoundExchangeRate(ctoken, token);
        expect(price).to.be.equal(
          priceUnderlying
            .mul(10 ** 10)
            .mul(10 ** 8)
            .div(exchangeRate),
        );
      });
    });

    pick(addresses.aave.atokens)
      .slice(0, 5)
      .forEach(({ atoken, token }) => {
        it(`should get the price of atokens ${atoken}`, async function () {
          const price = await priceOracle.connect(owner).getPrice(atoken, addresses.tokens.DAI);
          const priceUnderlying = await priceOracle.connect(owner).getPrice(token, addresses.tokens.DAI);
          expect(price).to.be.equal(priceUnderlying);
        });
      });
  });
});
