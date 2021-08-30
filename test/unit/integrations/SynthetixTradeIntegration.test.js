const { expect } = require('chai');
const { ethers } = require('hardhat');
const { increaseTime } = require('utils/test-helpers');

const { STRATEGY_EXECUTE_MAP, ONE_DAY_IN_SECONDS } = require('lib/constants.js');
const { eth } = require('lib/helpers');
const { fund } = require('lib/whale');
const { setupTests } = require('fixtures/GardenFixture');
const { getStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { createGarden } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');

describe('SynthetixTradeIntegration', function () {
  let synthetixTradeIntegration;
  let priceOracle;
  let owner;
  let signer1;
  let signer2;
  let signer3;

  beforeEach(async () => {
    ({ synthetixTradeIntegration, owner, signer1, signer2, signer3, priceOracle } = await setupTests()());
    await fund([signer1.address, signer2.address, signer3.address]);
  });

  describe('exchanges synthetic assets', function () {
    it(`cannot exchange between non synths (except DAI & synth)`, async function () {
      const garden = await createGarden({ reserveAsset: addresses.tokens.WETH, signer: signer1 });

      const strategyContract = await getStrategy({
        kind: 'buy',
        state: 'vote',
        integrations: synthetixTradeIntegration.address,
        garden: garden,
        specificParams: [addresses.tokens.sUSD, 0],
      });
      await expect(executeStrategy(strategyContract)).to.be.reverted;
    });

    // Synthetix from WETH garden
    [
      {
        token: addresses.tokens.DAI,
        name: 'DAI',
        pairs: [
          { asset: addresses.tokens.sETH, symbol: 'sETH' },
          { asset: addresses.tokens.sUSD, symbol: 'sUSD' },
          { asset: addresses.tokens.sBTC, symbol: 'sBTC' },
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
          console.log('before execute', synthetixTradeIntegration.address);
          const strategyContract = await getStrategy({
            kind: 'buy',
            state: 'vote',
            integrations: synthetixTradeIntegration.address,
            garden: garden,
            specificParams: [asset, 0],
          });

          await executeStrategy(strategyContract);
          console.log('after execute', token, asset);

          const tokenPriceInAsset = await priceOracle.connect(owner).getPrice(token, asset);

          const assetDecimals = await assetContract.decimals();
          const assetDecimalsDelta = 10 ** (18 - assetDecimals);

          const tokenDecimals = await tokenContract.decimals();
          const tokenDecimalsDelta = 10 ** (18 - tokenDecimals);

          const assetBalance = await assetContract.balanceOf(strategyContract.address);
          console.log('assetBalance', ethers.utils.formatEther(assetBalance));
          const expectedBalance = tokenPriceInAsset
            .mul(tokenDecimalsDelta)
            .mul(STRATEGY_EXECUTE_MAP[token])
            .div(eth())
            .div(assetDecimalsDelta);
          // 5% slippage. Doesn't matter we just want to check that the trade can execute
          // univ3 doesn't have right prices for some of these
          expect(assetBalance).to.be.closeTo(expectedBalance, expectedBalance.div(20));
          console.log('before finalize');
          await increaseTime(400);
          // await increaseBlock(10);
          // Cannot test Finalize on Synthetix because Oracle becomes stale
          // await finalizeStrategy(strategyContract, 0);
          // const assetBalanceAfter = await assetContract.balanceOf(strategyContract.address);
          // expect(assetBalanceAfter).to.be.lt(1000000); // Almost 0
        });
      });
    });
  });
});
