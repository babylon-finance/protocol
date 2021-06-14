const { expect } = require('chai');
const { ethers } = require('hardhat');

const addresses = require('../lib/addresses');
const { ONE_DAY_IN_SECONDS, ONE_ETH, NOW, STRATEGY_EXECUTE_MAP } = require('../lib/constants.js');
const { increaseTime, from, parse, eth } = require('./utils/test-helpers');
const { createGarden } = require('./fixtures/GardenHelper');
const { impersonateAddress } = require('../lib/rpc');

const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  getStrategy,
  executeStrategy,
  finalizeStrategy,
  injectFakeProfits,
} = require('./fixtures/StrategyHelper');

const { setupTests } = require('./fixtures/GardenFixture');

describe('Keeper', function () {
  let babController;
  let rewardsDistributor;
  let owner;
  let keeper;
  let signer1;
  let signer2;
  let signer3;
  let garden1;
  let ishtarGate;
  let weth;
  let dai;
  let balancerIntegration;
  let kyberTradeIntegration;
  let daiGarden;
  let usdcGarden;
  let usdc;
  let gardenNFT;

  beforeEach(async () => {
    ({
      babController,
      rewardsDistributor,
      gardenNFT,
      keeper,
      owner,
      signer1,
      signer2,
      signer3,
      garden1,
      ishtarGate,
      balancerIntegration,
      kyberTradeIntegration,
    } = await setupTests({ fund: true })());
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
      [
        { token: addresses.tokens.WETH, name: 'WETH', fee: eth() },
        { token: addresses.tokens.DAI, name: 'DAI', fee: eth(2000) },
        { token: addresses.tokens.USDC, name: 'USDC', fee: from(2000 * 1e6) },
        { token: addresses.tokens.WBTC, name: 'WBTC', fee: from(0.05 * 1e8) },
      ].forEach(({ token, name, fee }) => {
        it(`gets paid max fee at ${name} garden`, async function () {
          const garden = await createGarden({ reserveAsset: token });
          const tokenContract = await ethers.getContractAt('IERC20', token);

          const strategy = await getStrategy({ state, specificParams: addresses.tokens.USDT });

          await func(garden, strategy, keeper, fee, token);

          expect(await tokenContract.balanceOf(await keeper.getAddress())).to.equal(fee);
        });

        it(`refuse to pay more than max fee at ${name} garden`, async function () {
          const garden = await createGarden({ reserveAsset: token });
          const tokenContract = await ethers.getContractAt('IERC20', token);

          const strategy = await getStrategy({ state: 'deposit', specificParams: addresses.tokens.USDT });

          await expect(func(garden, strategy, keeper, fee.add(1), token)).to.be.revertedWith(/BAB#019/);
        });
      });
    });
  }
});
