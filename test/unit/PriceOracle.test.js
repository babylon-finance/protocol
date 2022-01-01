const { expect } = require('chai');

const addresses = require('lib/addresses');
const { from, parse, eth } = require('lib/helpers');
const { pick } = require('utils/test-helpers');
const { setupTests } = require('fixtures/GardenFixture');

const tokens = [
  // Needs later block number
  // {
  //   name: 'GF->DAI',
  //   tokenIn: '0xaaef88cea01475125522e117bfe45cf32044e238',
  //   tokenOut: addresses.tokens.DAI,
  //   value: from('3006074239866975462'),
  // },
  {
    name: 'FRAX->DAI',
    tokenIn: addresses.tokens.FRAX,
    tokenOut: addresses.tokens.DAI,
    value: from('980447178825784409'),
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
    value: parse('353.731279839378735346'),
  },
  {
    name: 'CRV->LDO',
    tokenIn: addresses.tokens.CRV,
    tokenOut: '0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32',
    value: from('1138137927957411575'),
  },
  {
    name: 'USDC->DPI',
    tokenIn: addresses.tokens.USDC,
    tokenOut: addresses.tokens.DPI,
    value: parse('0.002825307084080822'),
  },
  {
    name: 'WETH-> YEARN dai',
    tokenIn: addresses.tokens.WETH,
    tokenOut: '0x19d3364a399d251e894ac732651be8b0e4e85001',
    value: parse('3915.726812823348298410'),
  },
  {
    name: 'WETH-> YEARN USDC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: '0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9',
    value: parse('3894.764384467298591341'),
  },
  {
    name: 'YEARN dai-> WETH dai',
    tokenIn: '0x19d3364a399d251e894ac732651be8b0e4e85001',
    tokenOut: addresses.tokens.WETH,
    value: parse('0.0002553'),
  },
  {
    name: 'YEARN USDC-> WETH dai',
    tokenIn: '0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9',
    tokenOut: addresses.tokens.WETH,
    value: parse('0.0002560'),
  },
  {
    name: 'WETH->tripool direct',
    tokenIn: addresses.tokens.WETH,
    tokenOut: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
    value: parse('4155.9'),
  },
  {
    name: 'tripool->WETH',
    tokenIn: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000240620334480852'),
  },
  {
    name: 'WETH->tricrypto2',
    tokenIn: addresses.tokens.WETH,
    tokenOut: '0xc4ad29ba4b3c580e6d59105fff484999997675ff',
    value: parse('4209.9'),
  },
  {
    name: 'tricrypto2->WETH',
    tokenIn: '0xc4ad29ba4b3c580e6d59105fff484999997675ff',
    tokenOut: addresses.tokens.WETH,
    value: parse('0.00023740'),
  },
  {
    name: 'WETH->renBTC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.renBTC,
    value: from('72842000078806588'),
  },
  {
    name: 'WETH->CRV',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.CRV,
    value: parse('950'),
  },
  {
    name: 'WETH->sAAVE',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.sAAVE,
    value: from('16046209145716915613'),
  },
  {
    name: 'DAI->sAAVE',
    tokenIn: addresses.tokens.DAI,
    tokenOut: addresses.tokens.sAAVE,
    value: from('3786891460852303'),
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
    value: parse('4408.204310775759494487'),
  },
  {
    name: 'TUSD->WETH',
    tokenIn: addresses.tokens.TUSD,
    tokenOut: addresses.tokens.WETH,
    value: parse('0.000226668296094232'),
  },
  {
    name: 'YFI->DAI',
    tokenIn: addresses.tokens.YFI,
    tokenOut: addresses.tokens.DAI,
    value: from('32230902445927718914674'),
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
    value: from('58177225539404031721099'),
  },
  {
    name: 'COMP->USDC',
    tokenIn: addresses.tokens.COMP,
    tokenOut: addresses.tokens.USDC,
    value: from('299566529993303469131'),
  },
  {
    name: 'YFI',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.YFI,
    value: parse('0.1314'),
  },
  {
    name: 'WBTC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.WBTC,
    value: parse('0.072834406363599120'),
  },
  {
    name: 'DAI',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.DAI,
    value: parse('4237.303686043709874621'),
  },
  {
    name: 'USDC',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.USDC,
    value: parse('4236.163851352164116664'),
  },
  {
    name: 'USDT',
    tokenIn: addresses.tokens.WETH,
    tokenOut: addresses.tokens.USDT,
    value: parse('4234.532489433037288362'),
  },
  {
    name: 'USDT inverse',
    tokenIn: addresses.tokens.USDT,
    tokenOut: addresses.tokens.WETH,
    value: parse('0.0002360'),
  },
  {
    name: 'DAI inverse',
    tokenIn: addresses.tokens.DAI,
    tokenOut: addresses.tokens.WETH,
    value: parse('0.0002359'),
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
      it.only(`should get the price of ${name}`, async function () {
        const price = await priceOracle.connect(owner).getPrice(tokenIn, tokenOut);
        expect(price).to.be.closeTo(value, value.div(50));
      });
    });

    pick(addresses.compound.ctokens).forEach(({ ctoken, token }) => {
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
          const exchangeRate = await priceOracle.getCreamExchangeRate(ctoken);
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
