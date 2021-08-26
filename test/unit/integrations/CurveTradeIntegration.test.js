const { expect } = require('chai');
const { ethers } = require('hardhat');

const { STRATEGY_EXECUTE_MAP } = require('lib/constants.js');
const { eth } = require('lib/helpers');
const { fund } = require('lib/whale');
const { setupTests } = require('fixtures/GardenFixture');
const { getStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { createGarden } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');

describe('CurveTradeIntegration', function () {
  let curveTradeIntegration;
  let priceOracle;
  let owner;
  let signer1;
  let signer2;
  let signer3;

  beforeEach(async () => {
    ({ curveTradeIntegration, owner, signer1, signer2, signer3, priceOracle } = await setupTests()());
    await fund([signer1.address, signer2.address, signer3.address]);
  });

  describe('exchanges underlying tokens', function () {
    [
      {
        token: addresses.tokens.WETH,
        name: 'WETH',
        pairs: [
          { asset: addresses.tokens.ETH2, symbol: 'ETH' },
          { asset: addresses.tokens.aETHC, symbol: 'aETHc' },
          { asset: addresses.tokens.sETH, symbol: 'sETH' },
          { asset: addresses.tokens.stETH, symbol: 'stETH' },
        ],
      },
      // { token: addresses.tokens.DAI, name: 'DAI' },
      // { token: addresses.tokens.USDC, name: 'USDC' },
      // { token: addresses.tokens.WBTC, name: 'WBTC' },
    ].forEach(({ token, name, pairs }) => {
      pairs.forEach(({ asset, symbol }) => {
        it(`exchange ${name}->${symbol} in ${name} garden`, async function () {
          if (token === asset) return;

          const tokenContract = await ethers.getContractAt(
            '@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20',
            token,
          );
          const assetContract = await ethers.getContractAt(
            '@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20',
            asset,
          );

          const strategyContract = await getStrategy({
            kind: 'buy',
            state: 'vote',
            integration: curveTradeIntegration.address,
            specificParams: [asset, 0],
          });

          await executeStrategy(strategyContract);

          const tokenPriceInAsset = await priceOracle.connect(owner).getPrice(token, asset);

          const assetDecimals = await assetContract.decimals();
          const assetDecimalsDelta = 10 ** (18 - assetDecimals);

          const tokenDecimals = await tokenContract.decimals();
          const tokenDecimalsDelta = 10 ** (18 - tokenDecimals);

          const assetBalance = await assetContract.balanceOf(strategyContract.address);
          const expectedBalance = tokenPriceInAsset
            .mul(tokenDecimalsDelta)
            .mul(STRATEGY_EXECUTE_MAP[token])
            .div(eth())
            .div(assetDecimalsDelta);

          expect(expectedBalance).to.be.closeTo(assetBalance, assetBalance.div(40)); // 2.5% slippage

          await finalizeStrategy(strategyContract, 0);

          expect(0).to.eq(await assetContract.balanceOf(strategyContract.address));
        });
      });
    });
  });
});
