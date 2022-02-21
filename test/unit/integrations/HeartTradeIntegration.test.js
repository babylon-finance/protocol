const { expect } = require('chai');
const { ethers } = require('hardhat');

const { STRATEGY_EXECUTE_MAP, GARDENS } = require('lib/constants.js');
const { fund } = require('lib/whale');
const { setupTests } = require('fixtures/GardenFixture');
const { getStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { createGarden } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { impersonateAddress } = require('lib/rpc');
const { getERC20, eth, pick } = require('utils/test-helpers');

describe('HeartTradeIntegration', function () {
  let masterSwapper;
  let babController;
  let heart;
  let priceOracle;
  let owner;
  let signer1;
  let signer2;
  let signer3;

  beforeEach(async () => {
    ({ masterSwapper, babController, heart, owner, signer1, signer2, signer3, priceOracle } = await setupTests()());
    await fund([signer1.address, signer2.address, signer3.address]);
    await babController.connect(owner).updateProtocolWantedAsset(addresses.tokens.BABL, true);
    await heart.connect(owner).updateAssetToPurchase(addresses.tokens.FRAX);
    const fraxWhale = await impersonateAddress('0x183d0dc5867c01bfb1dbbc41d6a9d3de6e044626');
    const FRAX = await getERC20(addresses.tokens.FRAX);
    await FRAX.connect(fraxWhale).transfer(heart.address, ethers.utils.parseEther('20000'));
  });

  describe('exchange', function () {
    pick(GARDENS).forEach(({ token, name, fee }) => {
      it(`sell BABL to the heart in a ${name} garden`, async function () {
        const garden1 = await createGarden({ reserveAsset: token });
        const tokenContract = await getERC20(token);
        const assetContract = await getERC20(addresses.tokens.BABL);
        const heartBalanceBabl = await assetContract.balanceOf(heart.address);
        const strategyContract = await getStrategy({
          kind: 'buy',
          state: 'vote',
          integration: masterSwapper.address,
          specificParams: [assetContract.address, 0],
          garden: garden1,
        });
        await executeStrategy(strategyContract);
        const tokenPriceInAsset = await priceOracle.connect(owner).getPrice(token, assetContract.address);
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
        expect(assetBalance).to.eq((await assetContract.balanceOf(heart.address)).sub(heartBalanceBabl));
      });
    });
  });
});
