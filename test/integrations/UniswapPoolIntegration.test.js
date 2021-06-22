const { expect } = require('chai');
const { ethers } = require('hardhat');
const { setupTests } = require('../fixtures/GardenFixture');
const { createGarden, transferFunds, depositFunds } = require('../fixtures/GardenHelper');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  getStrategy,
  executeStrategy,
  finalizeStrategy,
} = require('../fixtures/StrategyHelper');
const addresses = require('../../lib/addresses');
const { ADDRESS_ZERO, STRATEGY_EXECUTE_MAP } = require('../../lib/constants');

describe('UniswapPoolIntegrationTest', function () {
  let uniswapPoolIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let babController;

  beforeEach(async () => {
    ({ babController, garden1, uniswapPoolIntegration, signer1, signer2, signer3 } = await setupTests()());
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      const deployedUni = await uniswapPoolIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedUni).to.equal(true);
    });
  });

  describe('Liquidity Pools', function () {
    let daiWethPair;

    beforeEach(async () => {
      daiWethPair = await ethers.getContractAt('IUniswapV2PairB', addresses.uniswap.pairs.wethdai);
    });

    it('check that a valid pool is valid', async function () {
      expect(await uniswapPoolIntegration.isPool(addresses.uniswap.pairs.wethdai)).to.equal(true);
    });

    it('check that an invalid pool is not valid', async function () {
      await expect(uniswapPoolIntegration.isPool(ADDRESS_ZERO)).to.be.reverted;
    });

    it('can enter and exit the weth dai pool', async function () {
      const strategyContract = await createStrategy(
        'lp',
        'vote',
        [signer1, signer2, signer3],
        uniswapPoolIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        daiWethPair.address,
      );
      await executeStrategy(strategyContract);
      expect(await daiWethPair.balanceOf(strategyContract.address)).to.be.gt(0);

      await finalizeStrategy(strategyContract, 0);
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
        { pool: addresses.uniswap.pairs.wethdai, symbol: 'WETH-DAI' }, //DAI-WETH pool
        { pool: addresses.uniswap.pairs.wethusdc, symbol: 'WETH-USDC' }, //WETH-USDC pool
        { pool: addresses.uniswap.pairs.wethwbtc, symbol: 'WETH-WBTC' }, //WETH-WBTC pool
        //    { pool: addresses.uniswap.pairs.wethrenBTC, symbol: 'WETH-renBTC' }, //WETH-renBTC pool only works from WETH and WBTC Gardens if not intermediate swaps are done
        { pool: addresses.uniswap.pairs.daiusdc, symbol: 'DAI-USDC' }, //DAI-USDC pool
        { pool: addresses.uniswap.pairs.daiwbtc, symbol: 'DAI-WBTC' }, //DAI-WBTC pool
      ].forEach(({ pool, symbol }) => {
        it(`can enter and exit the ${symbol} pool from a ${name} Garden`, async function () {
          const poolAddress = await ethers.getContractAt('IUniswapV2PairB', pool);
          await transferFunds(token);

          const garden = await createGarden({ reserveAsset: token });
          await depositFunds(token, garden);

          const strategyContract = await getStrategy({
            kind: 'lp',
            state: 'vote',
            integrations: uniswapPoolIntegration.address,
            garden,
            specificParams: poolAddress.address,
          });
          let amount = STRATEGY_EXECUTE_MAP[token];

          await executeStrategy(strategyContract, { amount });

          expect(await poolAddress.balanceOf(strategyContract.address)).to.be.gt(0);

          await finalizeStrategy(strategyContract, 0);
          expect(await poolAddress.balanceOf(strategyContract.address)).to.equal(0);
        });
      });
    });
  });
});
