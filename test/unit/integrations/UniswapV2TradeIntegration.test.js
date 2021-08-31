const { expect } = require('chai');
const { ethers } = require('hardhat');

const { STRATEGY_EXECUTE_MAP } = require('lib/constants.js');
const { eth } = require('lib/helpers');
const { fund } = require('lib/whale');
const { setupTests } = require('fixtures/GardenFixture');
const { getStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { createGarden } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');

describe('UniswapV2TradeIntegration', function () {
  let univ2TradeIntegration;
  let priceOracle;
  let owner;
  let signer1;
  let signer2;
  let signer3;

  beforeEach(async () => {
    ({ univ2TradeIntegration, owner, signer1, signer2, signer3, priceOracle } = await setupTests()());
    await fund([signer1.address, signer2.address, signer3.address]);
  });

  describe('exchanges assets through univ2 via WETH', function () {
    [
      {
        token: addresses.tokens.DAI,
        name: 'DAI',
        pairs: [
          { asset: addresses.tokens.DAI, symbol: 'DAI' },
          { asset: addresses.tokens.USDC, symbol: 'USDC' },
        ],
      },
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

          const garden = await createGarden({ reserveAsset: token, signer: signer1 });

          const strategyContract = await getStrategy({
            kind: 'buy',
            state: 'vote',
            integrations: univ2TradeIntegration.address,
            garden: garden,
            specificParams: [asset, 2],
          });

          await executeStrategy(strategyContract);
          console.log('after execute', token, asset);
          const tokenPriceInAsset = await priceOracle.connect(owner).getPriceNAV(token, asset);

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
          // 5% slippage. Doesn't matter we just want to check that the trade can execute
          // univ3 doesn't have right prices for some of these
          expect(expectedBalance).to.be.closeTo(assetBalance, assetBalance.div(20));
          await finalizeStrategy(strategyContract, 0);
          const assetBalanceAfter = await assetContract.balanceOf(strategyContract.address);
          expect(assetBalanceAfter).to.be.lt(1000000); // Almost 0
        });
      });
    });
  });

  describe('fails to execute without min amount', function () {
    it(`exchange fails with minAmount as 0`, async function () {
      const garden = await createGarden({ reserveAsset: addresses.tokens.WETH, signer: signer1 });
      const strategyContract = await getStrategy({
        kind: 'buy',
        state: 'vote',
        integrations: univ2TradeIntegration.address,
        garden: garden,
        specificParams: [addresses.tokens.DAI, 0],
      });
      await expect(executeStrategy(strategyContract)).to.be.revertedWith('Not enough liquidity');
    });
    it(`exchange fails with minAmount as 1`, async function () {
      const garden = await createGarden({ reserveAsset: addresses.tokens.WETH, signer: signer1 });

      const strategyContract = await getStrategy({
        kind: 'buy',
        state: 'vote',
        integrations: univ2TradeIntegration.address,
        garden: garden,
        specificParams: [addresses.tokens.DAI, 1],
      });
      await expect(executeStrategy(strategyContract)).to.be.revertedWith('Not enough liquidity');
    });
  });
});
