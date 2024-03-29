const { expect } = require('chai');
const { ethers } = require('hardhat');
const addresses = require('lib/addresses');
const { ONE_DAY_IN_SECONDS, STRATEGY_EXECUTE_MAP } = require('lib/constants.js');
const { fund } = require('lib/whale');
const { increaseTime, getERC20, from, eth, pick } = require('utils/test-helpers');
const { createGarden } = require('fixtures/GardenHelper');

const { getStrategy } = require('fixtures/StrategyHelper');

const { setupTests } = require('fixtures/GardenFixture');

describe('Keeper', function () {
  let keeper;
  let signer1;
  let signer2;
  let signer3;
  let priceOracle;

  beforeEach(async () => {
    ({ keeper, signer1, signer2, signer3, priceOracle } = await setupTests()());
    await fund([signer1.address, signer2.address, signer3.address]);
  });

  describe('totalKeeperFees', function () {
    it(`gets accumulated over multile operations`, async function () {
      const garden = await createGarden();
      const fee = eth(0.1);

      const strategy = await getStrategy({
        garden: garden,
        state: 'deposit',
        specificParams: [addresses.tokens.USDT, 0],
      });

      await strategy
        .connect(keeper)
        .resolveVoting(
          [signer1.getAddress(), signer2.getAddress()],
          [await garden.balanceOf(signer1.getAddress()), await garden.balanceOf(signer2.getAddress())],
          fee,
          {
            gasPrice: 0,
          },
        );

      expect(await garden.totalKeeperFees()).to.equal(fee);

      await increaseTime(ONE_DAY_IN_SECONDS);
      await strategy.connect(keeper).executeStrategy(STRATEGY_EXECUTE_MAP[addresses.tokens.WETH], fee, {
        gasPrice: 0,
      });

      expect(await garden.totalKeeperFees()).to.equal(fee.add(fee));
    });
  });

  for (const { func, name, state } of [
    {
      func: async (garden, strategy, keeper, fee) =>
        await strategy
          .connect(keeper)
          .resolveVoting(
            [signer1.getAddress(), signer2.getAddress()],
            [await garden.balanceOf(signer1.getAddress()), await garden.balanceOf(signer2.getAddress())],
            fee,
            {
              gasPrice: 0,
            },
          ),
      name: 'resolveVoting',
      state: 'deposit',
    },
    {
      func: async (garden, strategy, keeper, fee, token) => {
        await increaseTime(ONE_DAY_IN_SECONDS);
        await strategy.connect(keeper).executeStrategy(STRATEGY_EXECUTE_MAP[token], fee, {
          gasPrice: 0,
        });
      },
      name: 'executeStrategy',
      state: 'vote',
    },
  ]) {
    describe(name, function () {
      pick([
        { token: addresses.tokens.WETH, name: 'WETH', fee: eth() },
        { token: addresses.tokens.DAI, name: 'DAI', fee: eth(2000) },
        { token: addresses.tokens.USDC, name: 'USDC', fee: from(2000 * 1e6) },
        { token: addresses.tokens.WBTC, name: 'WBTC', fee: from(0.05 * 1e8) },
      ]).forEach(({ token, name, fee }) => {
        it(`gets paid max fee at ${name} garden`, async function () {
          const garden = await createGarden({ reserveAsset: token });
          const tokenContract = await getERC20(token);
          // initial balance (if any i.e. USDC)
          const keeperInitialBalance = await tokenContract.balanceOf(await keeper.getAddress());
          const strategy = await getStrategy({ garden: garden, state, specificParams: [addresses.tokens.USDT, 0] });

          const price = await priceOracle.getPrice(token, addresses.tokens.DAI);
          const fee = eth(2000)
            .mul(eth())
            .div(price)
            .mul(99)
            .div(100)
            .mul((10 ** (await tokenContract.decimals())).toString())
            .div(eth());
          await func(garden, strategy, keeper, fee, token);

          expect(await tokenContract.balanceOf(await keeper.getAddress())).to.equal(fee.add(keeperInitialBalance));
        });

        it(`refuse to pay more than max fee at ${name} garden`, async function () {
          const garden = await createGarden({ reserveAsset: token });
          const tokenContract = await getERC20(token);

          const price = await priceOracle.getPrice(token, addresses.tokens.DAI);
          const fee = eth(2000)
            .mul(eth())
            .div(price)
            .mul(99)
            .div(100)
            .mul((10 ** (await tokenContract.decimals())).toString())
            .div(eth());

          const strategy = await getStrategy({ garden: garden, state, specificParams: [addresses.tokens.USDT, 0] });

          await expect(func(garden, strategy, keeper, fee.mul(110).div(100), token)).to.be.revertedWith('BAB#019');
        });
      });
    });
  }
});
