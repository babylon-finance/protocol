const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ONE_ETH } = require('../../lib/constants');
const { from, parse, eth } = require('../../lib/helpers');
const { setupTests } = require('../fixtures/GardenFixture');
const {
  getStrategy,
  createStrategy,
  DEFAULT_STRATEGY_PARAMS,
  executeStrategy,
  finalizeStrategy,
} = require('../fixtures/StrategyHelper');
const { createGarden } = require('../fixtures/GardenHelper');
const addresses = require('../../lib/addresses');

describe.only('UniswapV3TradeIntegration', function () {
  let uniswapV3TradeIntegration;
  let signer1;
  let signer2;
  let signer3;
  let dai;
  let weth;

  beforeEach(async () => {
    ({ uniswapV3TradeIntegration, signer1, signer2, signer3, dai, weth } = await setupTests({ fund: true })());
  });

  describe('exchange', function () {
    [
      { token: addresses.tokens.WETH, name: 'WETH' },
      { token: addresses.tokens.DAI, name: 'DAI' },
      { token: addresses.tokens.USDC, name: 'USDC' },
      { token: addresses.tokens.WBTC, name: 'WBTC' },
    ].forEach(({ token, name, fee }) => {
      [
        { asset: addresses.tokens.USDT, symbol: 'USDT' },
      ].forEach(({ asset, symbol }) => {
        it(`exchange ${name} to ${symbol} in ${name} garden`, async function () {
          const garden = await createGarden({ reserveAsset: token });
          const tokenContract = await ethers.getContractAt('IERC20', token);

          const strategyContract = await getStrategy({
            kind: 'buy',
            state: 'vote',
            integration: uniswapV3TradeIntegration.address,
            specificParams: asset,
          });

          await executeStrategy(strategyContract);

          await finalizeStrategy(strategyContract, 0);
        });
      });
    });
  });
});
