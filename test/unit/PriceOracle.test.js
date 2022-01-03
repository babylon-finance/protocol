const { expect } = require('chai');

const addresses = require('lib/addresses');
const { from, parse, eth } = require('lib/helpers');
const { pick } = require('utils/test-helpers');
const { setupTests } = require('fixtures/GardenFixture');

const tokens = [
  {
    name: 'GF->DAI',
    tokenIn: '0xaaef88cea01475125522e117bfe45cf32044e238',
    tokenOut: addresses.tokens.DAI,
    value: from('2550766996046267519'),
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
    value: from('1006074239866975462'),
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
    value: parse('293.731279839378735346'),
  },
  {
    name: 'CRV->LDO',
    tokenIn: addresses.tokens.CRV,
    tokenOut: '0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32',
    value: from('1723354680330005164'),
  },
  {
    name: 'USDC->DPI',
    tokenIn: addresses.tokens.USDC,
    tokenOut: addresses.tokens.DPI,
    value: parse('0.003408719478323585'),
  },
  {
    name: 'WETH-> YEARN dai',
    tokenIn: addresses.tokens.WETH,
    tokenOut: '0xdA816459F1AB5631232FE5e97a05BBBb94970c95',
    value: parse('3699.915612614859653532'),
  },
  {
    name: 'WETH-> YEARN USDC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: '0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9',
    value: parse('3453.495439740702037995'),
  },
  {
    name: 'YEARN dai-> WETH dai',
    tokenIn: '0xdA816459F1AB5631232FE5e97a05BBBb94970c95',
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000270114117790294'),
  },
  {
    name: 'YEARN USDC-> WETH dai',
    tokenIn: '0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9',
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000289000000000000'),
  },
  {
    name: 'WETH->tripool direct',
    tokenIn: addresses.tokens.WETH,
    tokenOut: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
    value: parse('3701.546655754214311685'),
  },
  {
    name: 'tripool->WETH',
    tokenIn: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000269995095170930'),
  },
  {
    name: 'WETH->tricrypto2',
    tokenIn: addresses.tokens.WETH,
    tokenOut: '0xc4ad29ba4b3c580e6d59105fff484999997675ff',
    value: parse('3747.695705022502467870'),
  },
  {
    name: 'tricrypto2->WETH',
    tokenIn: '0xc4ad29ba4b3c580e6d59105fff484999997675ff',
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000266670662553977'),
  },
  {
    name: 'WETH->renBTC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.renBTC,
    value: from('79670792393502101'),
  },
  {
    name: 'WETH->CRV',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.CRV,
    value: parse('626'),
  },
  {
    name: 'WETH->sAAVE',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.sAAVE,
    value: from('14775062539717267519'),
  },
  {
    name: 'DAI->sAAVE',
    tokenIn: addresses.tokens.DAI,
    tokenOut: addresses.tokens.sAAVE,
    value: from('3913405170608426'),
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
    value: parse('3774.407804575983940687'),
  },
  {
    name: 'TUSD->WETH',
    tokenIn: addresses.tokens.TUSD,
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000264730313109126'),
  },
  {
    name: 'YFI->DAI',
    tokenIn: addresses.tokens.YFI,
    tokenOut: addresses.tokens.DAI,
    value: from('37925266838468858270565'),
  },
  {
    name: 'SNX->USDT',
    tokenIn: addresses.tokens.SNX,
    tokenOut: addresses.tokens.USDT,
    value: from('9967509852298153273'),
  },
  {
    name: 'WBTC->DAI',
    tokenIn: addresses.tokens.WBTC,
    tokenOut: addresses.tokens.DAI,
    value: from('47164683060906489532073'),
  },
  {
    name: 'COMP->USDC',
    tokenIn: addresses.tokens.COMP,
    tokenOut: addresses.tokens.USDC,
    value: from('209000267451196080842'),
  },
  {
    name: 'YFI',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.YFI,
    value: parse('0.099551055313425919'),
  },
  {
    name: 'WBTC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.WBTC,
    value: parse('0.079693175815793483'),
  },
  {
    name: 'WETH->DAI',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.DAI,
    value: parse('3775.277281503964185794'),
  },
  {
    name: 'USDC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.USDC,
    value: parse('3775.163851352164116664'),
  },
  {
    name: 'USDT',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.USDT,
    value: parse('3775.532489433037288362'),
  },
  {
    name: 'USDT inverse',
    tokenIn: addresses.tokens.USDT,
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000264809780320504'),
  },
  {
    name: 'DAI inverse',
    tokenIn: addresses.tokens.DAI,
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000264809780320504'),
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

    pick(addresses.compound.ctokens)
      .slice(0, 5)
      .forEach(({ ctoken, token }) => {
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

    pick(addresses.cream.crtokens)
      .slice(0, 5)
      .forEach(({ ctoken, token }) => {
        it(`should get the price of crtokens ${ctoken}`, async function () {
          const price = await priceOracle.connect(owner).getPrice(ctoken, addresses.tokens.DAI);
          const priceUnderlying = await priceOracle.connect(owner).getPrice(token, addresses.tokens.DAI);
          const exchangeRate = await priceOracle.getCreamExchangeRate(ctoken, token);
          expect(price).to.be.equal(
            priceUnderlying
              .mul(exchangeRate)
              .div(10 ** 10)
              .div(10 ** 8),
          );
        });
      });

    pick(addresses.synthetix.synths)
      .slice(0, 5)
      .forEach(({ synth, token }) => {
        // TODO: synths get price is broken due to updated block nuumber
        it.skip(`should get the price of synthetix ${synth}`, async function () {
          const price = await priceOracle.connect(owner).getPrice(synth, addresses.tokens.DAI);
          expect(price).to.be.gt(0);
          if (token) {
            const priceUnderlying = await priceOracle.connect(owner).getPrice(token, addresses.tokens.DAI);
            expect(price).to.be.closeTo(priceUnderlying, eth('0.01'));
          }
        });
      });
  });
});
