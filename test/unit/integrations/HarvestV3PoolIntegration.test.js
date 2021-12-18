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
const { normalizeDecimals, getERC20, eth } = require('utils/test-helpers');
const addresses = require('lib/addresses');
const { ADDRESS_ZERO, STRATEGY_EXECUTE_MAP } = require('lib/constants');

// TODO: Fais due to old block number. Fix the block nubmer issue
describe.only('HarvestUniV3PoolIntegrationTest', function () {
  let harvestV3VaultIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let priceOracle;
  let owner;
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
      harvestV3VaultIntegration,
      owner,
      signer1,
      signer2,
      signer3,
      priceOracle,
    } = await setupTests()());
  });

  describe('Liquidity Pools', function () {
    let fDaiWethVault;

    beforeEach(async () => {
      fDaiWethVault = await ethers.getContractAt('IHarvestUniv3Pool', addresses.harvest.v3vaults.fDaiWeth);
    });

    it('check that a valid pool is valid', async function () {
      const abiCoder = ethers.utils.defaultAbiCoder;
      const data = abiCoder.encode(['address', 'uint256'], [addresses.harvest.v3vaults.fDaiWeth, 0]);

      expect(await harvestV3VaultIntegration.isPool(data)).to.equal(true);
    });

    it('check that an invalid pool is not valid', async function () {
      await expect(harvestV3VaultIntegration.isPool([ADDRESS_ZERO, 0])).to.be.reverted;
    });

    it('can enter and exit the WETH/DAI v3 pool', async function () {
      const strategyContract = await createStrategy(
        'lp',
        'vote',
        [signer1, signer2, signer3],
        harvestV3VaultIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [fDaiWethVault.address, 0],
      );
      await executeStrategy(strategyContract);
      expect(await fDaiWethVault.balanceOf(strategyContract.address)).to.be.gt(0);

      await finalizeStrategy(strategyContract, 0);
      expect(await fDaiWethVault.balanceOf(strategyContract.address)).to.equal(0);
    });

    it('can enter and get NAV of the WETH/DAI v3 pool', async function () {
      const strategyContract = await createStrategy(
        'lp',
        'vote',
        [signer1, signer2, signer3],
        harvestV3VaultIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [fDaiWethVault.address, 0],
      );
      await executeStrategy(strategyContract);
      expect(await fDaiWethVault.balanceOf(strategyContract.address)).to.be.gt(0);
      expect(await strategyContract.getNAV()).to.be.closeTo(eth(), eth().div(50));
    });
  });

  describe('Harvest Uni V3 vaults multi reserve asset garden and multi-pair', function () {
    [
      { token: addresses.tokens.WETH, name: 'WETH' },
      { token: addresses.tokens.DAI, name: 'DAI' },
      { token: addresses.tokens.USDC, name: 'USDC' },
      { token: addresses.tokens.WBTC, name: 'WBTC' },
    ].forEach(({ token, name }) => {
      Object.keys(addresses.harvest.v3vaults).forEach((symbol) => {
        it(`can enter and exit the ${symbol} at Uniswap pool from a ${name} Garden`, async function () {
          const harvestVault = await ethers.getContractAt('IHarvestUniv3Pool', addresses.harvest.v3vaults[symbol]);
          await transferFunds(token);

          const garden = await createGarden({ reserveAsset: token });
          await depositFunds(token, garden);

          const strategyContract = await getStrategy({
            kind: 'lp',
            state: 'vote',
            integrations: harvestV3VaultIntegration.address,
            garden,
            specificParams: [harvestVault.address, 0],
          });
          const amount = STRATEGY_EXECUTE_MAP[token];

          await executeStrategy(strategyContract, { amount });

          expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(50));

          const tokenContract = await getERC20(token);
          const executionTokenBalance = await tokenContract.balanceOf(garden.address);

          expect(await harvestVault.balanceOf(strategyContract.address)).to.be.gt(0);

          await finalizeStrategy(strategyContract, 0);
          expect(await harvestVault.balanceOf(strategyContract.address)).to.equal(0);

          expect(await tokenContract.balanceOf(garden.address)).to.be.gt(executionTokenBalance);
        });
      });
    });
  });
});
