const { expect } = require('chai');
const { ethers } = require('hardhat');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, transferFunds, depositFunds } = require('fixtures/GardenHelper');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  getStrategy,
  executeStrategy,
  finalizeStrategy,
} = require('fixtures/StrategyHelper');
const { normalizeDecimals, getERC20, getContract, parse, from, eth, pick } = require('utils/test-helpers');
const addresses = require('lib/addresses');
const { ADDRESS_ZERO, STRATEGY_EXECUTE_MAP, GARDENS } = require('lib/constants');

describe('UniswapPoolIntegrationTest', function () {
  let uniswapPoolIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let priceOracle;
  let owner;
  let babController;
  let WETH;
  let DAI;
  let keeper;

  async function getExpectedLPTokens(token, amount, poolAddress, token0, token1) {
    const reservePriceInAsset0 = await priceOracle.connect(owner).getPrice(token, token0);
    const reservePriceInAsset1 = await priceOracle.connect(owner).getPrice(token, token1);

    const token0Contract = await getERC20(token0);
    const token0Decimals = await token0Contract.decimals();

    const token1Contract = await getERC20(token1);
    const token1Decimals = await token1Contract.decimals();

    const tokenContract = await getERC20(token);
    const tokenDecimals = await tokenContract.decimals();

    const amount0ToAdd = await normalizeDecimals(
      tokenDecimals,
      token0Decimals,
      amount.mul(reservePriceInAsset0).div(2).div(eth(1)),
    );
    const amount1ToAdd = await normalizeDecimals(
      tokenDecimals,
      token1Decimals,
      amount.mul(reservePriceInAsset1).div(2).div(eth(1)),
    );

    const poolTotalSupply = await poolAddress.totalSupply();
    const balanceToken0 = await token0Contract.balanceOf(poolAddress.address);
    const balanceToken1 = await token1Contract.balanceOf(poolAddress.address);

    const liquidityToken1 = amount0ToAdd.mul(poolTotalSupply).div(balanceToken0);
    const liquidityToken2 = amount1ToAdd.mul(poolTotalSupply).div(balanceToken1);

    return liquidityToken1 < liquidityToken2 ? liquidityToken1 : liquidityToken2;
  }

  beforeEach(async () => {
    ({
      babController,
      garden1,
      uniswapPoolIntegration,
      owner,
      signer1,
      signer2,
      signer3,
      priceOracle,
      keeper,
    } = await setupTests()());

    WETH = await getERC20(addresses.tokens.WETH);
    DAI = await getERC20(addresses.tokens.DAI);
  });

  describe('Liquidity Pools', function () {
    let daiWethPair;

    beforeEach(async () => {
      daiWethPair = await ethers.getContractAt('IUniswapV2PairB', addresses.uniswap.pairs.wethdai);
    });

    it('check that a valid pool is valid', async function () {
      const abiCoder = ethers.utils.defaultAbiCoder;
      const data = abiCoder.encode(['address', 'uint256'], [addresses.uniswap.pairs.wethdai, 0]);

      expect(await uniswapPoolIntegration.isPool(data)).to.equal(true);
    });

    it('check that an invalid pool is not valid', async function () {
      await expect(uniswapPoolIntegration.isPool([ADDRESS_ZERO, 0])).to.be.reverted;
    });

    it('can enter and exit the weth dai pool', async function () {
      const strategyContract = await createStrategy(
        'lp',
        'vote',
        [signer1, signer2, signer3],
        uniswapPoolIntegration.address,
        garden1,
        keeper,
        DEFAULT_STRATEGY_PARAMS,
        [daiWethPair.address, 0],
      );
      await executeStrategy(strategyContract);
      expect(await daiWethPair.balanceOf(strategyContract.address)).to.be.gt(0);

      await finalizeStrategy(strategyContract, 0);
      expect(await daiWethPair.balanceOf(strategyContract.address)).to.equal(0);
    });
  });

  describe('Liquidity Pools multi reserve asset garden and multi-pair', function () {
    pick(GARDENS).forEach(({ token, name }) => {
      pick([
        {
          pool: addresses.uniswap.pairs.wethdai,
          symbol: 'WETH-DAI',
          token0: addresses.tokens.WETH,
          token1: addresses.tokens.DAI,
        }, // DAI-WETH pool
        {
          pool: addresses.uniswap.pairs.wethusdc,
          symbol: 'WETH-USDC',
          token0: addresses.tokens.WETH,
          token1: addresses.tokens.USDC,
        }, // WETH-USDC pool
        {
          pool: addresses.uniswap.pairs.wethwbtc,
          symbol: 'WETH-WBTC',
          token0: addresses.tokens.WETH,
          token1: addresses.tokens.WBTC,
        }, // WETH-WBTC pool
        {
          pool: addresses.uniswap.pairs.daiusdc,
          symbol: 'DAI-USDC',
          token0: addresses.tokens.DAI,
          token1: addresses.tokens.USDC,
        }, // DAI-USDC pool
        {
          pool: addresses.uniswap.pairs.daiwbtc,
          symbol: 'DAI-WBTC',
          token0: addresses.tokens.DAI,
          token1: addresses.tokens.WBTC,
        }, // DAI-WBTC pool
      ]).forEach(({ pool, symbol, token0, token1 }) => {
        it(`can enter and exit the ${symbol} at Uniswap pool from a ${name} Garden`, async function () {
          const poolAddress = await ethers.getContractAt('IUniswapV2PairB', pool);
          await transferFunds(token);

          const garden = await createGarden({ reserveAsset: token });
          await depositFunds(token, garden);

          const strategyContract = await getStrategy({
            kind: 'lp',
            state: 'vote',
            integrations: uniswapPoolIntegration.address,
            garden,
            specificParams: [poolAddress.address, 0],
          });
          const amount = STRATEGY_EXECUTE_MAP[token];

          await executeStrategy(strategyContract, { amount });
          // Check NAV
          expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(50));

          const tokenContract = await getERC20(token);
          const executionTokenBalance = await tokenContract.balanceOf(garden.address);
          const LPTokens = await getExpectedLPTokens(token, amount, poolAddress, token0, token1);
          expect(await poolAddress.balanceOf(strategyContract.address)).to.be.closeTo(LPTokens, LPTokens.div(50)); // 2% slippage

          await finalizeStrategy(strategyContract, 0);
          expect(await poolAddress.balanceOf(strategyContract.address)).to.equal(0);
          expect(await tokenContract.balanceOf(garden.address)).to.be.gt(executionTokenBalance);
        });
      });
    });
  });
});
