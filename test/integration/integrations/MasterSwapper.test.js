const { expect } = require('chai');
const { ethers } = require('hardhat');

const { STRATEGY_EXECUTE_MAP } = require('lib/constants.js');
const { getERC20, eth, pick } = require('utils/test-helpers');
const { fund } = require('lib/whale');
const { setupTests } = require('fixtures/GardenFixture');
const { getStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { createGarden } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');

describe('MasterSwapper', function () {
  let masterSwapper;
  let priceOracle;
  let owner;
  let signer1;
  let signer2;
  let signer3;

  beforeEach(async () => {
    ({ masterSwapper, owner, signer1, signer2, signer3, priceOracle } = await setupTests()());
    await fund([signer1.address, signer2.address, signer3.address]);
  });

  describe('swaps', function () {
    pick([
      {
        token: addresses.tokens.WETH,
        name: 'WETH',
        pairs: pick([
          { to: addresses.tokens.USDC, symbol: 'USDC' },
          // { to: addresses.tokens.sAAVE, symbol: 'sAAVE', synth: true }, // TODO Fix test
          { to: addresses.tokens.sUSD, symbol: 'sUSD' },
          { to: addresses.tokens.USDT, symbol: 'USDT' },
          { to: addresses.tokens.aETHC, symbol: 'aETHc' },
          { to: addresses.tokens.sETH, symbol: 'sETH' },
          { to: addresses.tokens.stETH, symbol: 'stETH' },
          { to: addresses.tokens.renBTC, symbol: 'renBTC' },
        ]),
      },
      {
        token: addresses.tokens.DAI,
        name: 'DAI',
        pairs: [
          { to: addresses.tokens.USDC, symbol: 'USDC' },
          { to: addresses.tokens.DAI, symbol: 'DAI' },
          { to: addresses.tokens.sUSD, symbol: 'sUSD' },
          { to: addresses.tokens.USDT, symbol: 'USDT' },
          { to: addresses.tokens.aETHC, symbol: 'aETHc' },
          { to: addresses.tokens.sETH, symbol: 'sETH' },
          { to: addresses.tokens.stETH, symbol: 'stETH' },
          //      { to: addresses.tokens.renBTC, symbol: 'renBTC' }, // TODO check Masterswapper could not swap
        ],
      },
      {
        token: addresses.tokens.USDC,
        name: 'USDC',
        pairs: [
          { to: addresses.tokens.USDC, symbol: 'USDC' },
          { to: addresses.tokens.DPI, symbol: 'DPI' },
          { to: addresses.tokens.DAI, symbol: 'DAI' },
          { to: addresses.tokens.sUSD, symbol: 'sUSD' },
          { to: addresses.tokens.USDT, symbol: 'USDT' },
          // { to: addresses.tokens.aETHC, symbol: 'aETHc' },
          { to: addresses.tokens.sETH, symbol: 'sETH' },
          { to: addresses.tokens.stETH, symbol: 'stETH' },
          { to: addresses.tokens.renBTC, symbol: 'renBTC' },
        ],
      },
      {
        token: addresses.tokens.WBTC,
        name: 'WBTC',
        pairs: [
          { to: addresses.tokens.USDC, symbol: 'USDC' },
          { to: addresses.tokens.DAI, symbol: 'DAI' },
          { to: addresses.tokens.sUSD, symbol: 'sUSD' },
          { to: addresses.tokens.USDT, symbol: 'USDT' },
          { to: addresses.tokens.aETHC, symbol: 'aETHc' },
          { to: addresses.tokens.sETH, symbol: 'sETH' },
          { to: addresses.tokens.stETH, symbol: 'stETH' },
          { to: addresses.tokens.renBTC, symbol: 'renBTC' },
        ],
      },
    ]).forEach(({ token, name, pairs }) => {
      pick(pairs).forEach(({ to, symbol, synth }) => {
        it(`exchange ${name}->${symbol} in ${name} garden`, async function () {
          if (token === to) return;

          const tokenContract = await getERC20(token);
          const assetContract = await getERC20(to);

          const garden = await createGarden({ reserveAsset: token, signer: signer1 });

          const strategyContract = await getStrategy({
            kind: 'buy',
            state: 'vote',
            integrations: masterSwapper.address,
            garden: garden,
            specificParams: [to, 0],
          });
          const tokenPriceInAsset = await priceOracle.connect(owner).getPrice(token, to);
          await executeStrategy(strategyContract);
          let assetBalance = await assetContract.balanceOf(strategyContract.address);

          const assetDecimals = await assetContract.decimals();
          const assetDecimalsDelta = 10 ** (18 - assetDecimals);

          const tokenDecimals = await tokenContract.decimals();
          const tokenDecimalsDelta = 10 ** (18 - tokenDecimals);

          assetBalance = await assetContract.balanceOf(strategyContract.address);
          const expectedBalance = tokenPriceInAsset
            .mul(tokenDecimalsDelta)
            .mul(STRATEGY_EXECUTE_MAP[token])
            .div(eth())
            .div(assetDecimalsDelta);
          // 5% slippage. Doesn't matter we just want to check that the trade can execute
          // univ3 doesn't have right prices for some of these
          expect(assetBalance).to.be.gt(0);
          expect(assetBalance).to.be.closeTo(expectedBalance, expectedBalance.div(20));
          if (synth) {
            // Cannot test exiting synth without replacing oracle
            return;
          }
          await finalizeStrategy(strategyContract, 0);
          const assetBalanceAfter = await assetContract.balanceOf(strategyContract.address);
          expect(assetBalanceAfter).to.be.lt(1000000); // Almost 0
        });
      });
    });
  });
});
