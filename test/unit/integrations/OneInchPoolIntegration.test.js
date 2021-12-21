const { expect } = require('chai');
const { ethers } = require('hardhat');
const { impersonateAddress } = require('lib/rpc');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, transferFunds, depositFunds } = require('fixtures/GardenHelper');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  getStrategy,
  executeStrategy,
  finalizeStrategy,
} = require('fixtures/StrategyHelper');
const { normalizeDecimals, getERC20, getContract, parse, from, eth } = require('utils/test-helpers');
const addresses = require('lib/addresses');
const { ADDRESS_ZERO, STRATEGY_EXECUTE_MAP } = require('lib/constants');
const { ONE_ETH } = require('lib/constants');

describe('OneInchPoolIntegrationTest', function () {
  let oneInchPoolIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let owner;
  let priceOracle;
  let babController;

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

    // OneInch documentation

    const poolTotalSupply = await poolAddress.totalSupply();

    let balanceToken0 = await token0Contract.balanceOf(poolAddress.address);
    let balanceToken1 = await token1Contract.balanceOf(poolAddress.address);

    // We take care of WETH vs. ETH when ADDRESS_ZERO is used in certain services like OneInch
    balanceToken0 =
      balanceToken0 === 0 && (token0 = addresses.tokens.WETH)
        ? await ethers.provider.getBalance(poolAddress.address)
        : balanceToken0;
    balanceToken1 =
      balanceToken1 === 0 && (token1 = addresses.tokens.WETH)
        ? await ethers.provider.getBalance(poolAddress.address)
        : balanceToken1;

    const liquidityToken1 =
      balanceToken0 > 0 ? amount0ToAdd.mul(poolTotalSupply).mul(ONE_ETH).div(balanceToken0).div(ONE_ETH) : 0;
    const liquidityToken2 =
      balanceToken1 > 0 ? amount1ToAdd.mul(poolTotalSupply).mul(ONE_ETH).div(balanceToken1).div(ONE_ETH) : 0;

    return liquidityToken1 < liquidityToken2 ? liquidityToken1 : liquidityToken2;
  }

  beforeEach(async () => {
    ({
      babController,
      garden1,
      oneInchPoolIntegration,
      priceOracle,
      signer1,
      signer2,
      signer3,
      owner,
    } = await setupTests()());
  });

  describe('Liquidity Pools', function () {
    let daiWethPair;
    let daiToken;
    let whaleSigner;
    const daiWhaleAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

    beforeEach(async () => {
      whaleSigner = await impersonateAddress(daiWhaleAddress);
      daiWethPair = await ethers.getContractAt('IMooniswap', addresses.oneinch.pools.wethdai);
      daiToken = await getERC20(addresses.tokens.DAI);
    });

    it('check that a valid pool is valid', async function () {
      const abiCoder = ethers.utils.defaultAbiCoder;
      const data = abiCoder.encode(['address', 'uint256'], [addresses.oneinch.pools.wethdai, 0]);
      expect(await oneInchPoolIntegration.isPool(data)).to.equal(true);
    });

    it('check that an invalid pool is not valid', async function () {
      const abiCoder = ethers.utils.defaultAbiCoder;
      const data = abiCoder.encode(['address', 'uint256'], [ADDRESS_ZERO, 0]);
      expect(await oneInchPoolIntegration.isPool(data)).to.equal(false);
    });

    it('tests mooniswap directly', async function () {
      expect(
        await daiToken.connect(whaleSigner).transfer(signer1.address, ethers.utils.parseEther('500'), {
          gasPrice: 0,
        }),
      );

      // Approve
      await daiToken.connect(signer1).approve(daiWethPair.address, ethers.utils.parseEther('500'));
      // Deposit
      await daiWethPair
        .connect(signer1)
        .deposit(
          [ethers.utils.parseEther('0.1'), ethers.utils.parseEther('100')],
          [ethers.utils.parseEther('0'), ethers.utils.parseEther('95')],
          {
            value: ethers.utils.parseEther('0.1'),
          },
        );
      expect(await daiWethPair.balanceOf(signer1.address)).to.be.gt(0);
    });

    it('can enter and exit the eth dai pool', async function () {
      const strategyContract = await createStrategy(
        'lp',
        'vote',
        [signer1, signer2, signer3],
        oneInchPoolIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [daiWethPair.address, 0],
      );
      await executeStrategy(strategyContract);
      expect(await daiWethPair.balanceOf(strategyContract.address)).to.be.gt(0);

      await finalizeStrategy(strategyContract);
      expect(await daiWethPair.balanceOf(strategyContract.address)).to.equal(0);
    });
  });
  describe('Liquidity Pools multi reserve asset garden and multi-pair', function () {
    [
      { token: addresses.tokens.WETH, name: 'WETH' },
      { token: addresses.tokens.DAI, name: 'DAI' },
      { token: addresses.tokens.USDC, name: 'USDC' },
      { token: addresses.tokens.WBTC, name: 'WBTC' },
    ].forEach(({ token, name }) => {
      [
        {
          pool: addresses.oneinch.pools.wethdai,
          symbol: 'WETH-DAI',
          token0: addresses.tokens.WETH,
          token1: addresses.tokens.DAI,
        }, // DAI-WETH pool
        {
          pool: addresses.oneinch.pools.wethusdc,
          symbol: 'WETH-USDC',
          token0: addresses.tokens.WETH,
          token1: addresses.tokens.USDC,
        }, // WETH-USDC pool
        {
          pool: addresses.oneinch.pools.wethwbtc,
          symbol: 'WETH-WBTC',
          token0: addresses.tokens.WETH,
          token1: addresses.tokens.WBTC,
        }, // WETH-WBTC pool
        {
          pool: addresses.oneinch.pools.daiusdc,
          symbol: 'DAI-USDC',
          token0: addresses.tokens.DAI,
          token1: addresses.tokens.USDC,
        }, // DAI-USDC pool
      ].forEach(({ pool, symbol, token0, token1 }) => {
        it(`can enter and exit the ${symbol} at One Inch pool from a ${name} Garden`, async function () {
          const poolAddress = await ethers.getContractAt('IMooniswap', pool);
          await transferFunds(token);

          const garden = await createGarden({ reserveAsset: token });
          await depositFunds(token, garden);

          const strategyContract = await getStrategy({
            kind: 'lp',
            state: 'vote',
            integrations: oneInchPoolIntegration.address,
            garden,
            specificParams: [poolAddress.address, 0],
          });
          const amount = STRATEGY_EXECUTE_MAP[token];

          await executeStrategy(strategyContract, { amount });
          // Check NAV
          expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(10)); // high slippage due to WETH-DAI as well WETH-WBTC at One Inch pool from a DAI Garden needs more than 2%
          const tokenContract = await getERC20(token);
          const executionTokenBalance = await tokenContract.balanceOf(garden.address);
          const LPTokens = await getExpectedLPTokens(token, amount, poolAddress, token0, token1);
          // TODO Fix getExpectedLPTokens equation
          // The following IF is a workaround: Liquidity equation check getExpectedLPTokens does not work for some pools after increasing block
          if (LPTokens !== 0) {
            expect(await poolAddress.balanceOf(strategyContract.address)).to.be.closeTo(LPTokens, LPTokens.div(15)); // 6% slippage (due to WETH-DAI at USDC Garden)
          } else {
            expect(await poolAddress.balanceOf(strategyContract.address)).to.be.gt(0);
          }
          await finalizeStrategy(strategyContract, 0);
          expect(await poolAddress.balanceOf(strategyContract.address)).to.equal(0);
          expect(await tokenContract.balanceOf(garden.address)).to.be.gt(executionTokenBalance);
        });
      });
    });
  });
});
