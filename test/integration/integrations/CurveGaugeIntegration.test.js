const { expect } = require('chai');
const { ethers } = require('hardhat');
const { createStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { increaseTime, getERC20, pick } = require('utils/test-helpers');
const { STRATEGY_EXECUTE_MAP, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');

describe('CurveGaugeIntegrationTest', function () {
  let curveGaugeIntegration;
  let curvePoolIntegration;
  let curveMetaRegistry;
  let signer1;
  let signer2;
  let signer3;

  const pools = Object.keys(addresses.curve.pools.v3)
    .map((key) => {
      return {
        name: key,
        pool: addresses.curve.pools.v3[key],
      };
    })
    .filter((p) => addresses.curve.pools.gaugeBlacklist.indexOf(p.pool) === -1);
  const cryptopools = Object.keys(addresses.curve.pools.crypto)
    .map((key) => {
      return {
        name: key,
        pool: addresses.curve.pools.crypto[key],
      };
    })
    .filter((p) => addresses.curve.pools.gaugeBlacklist.indexOf(p.pool) === -1);
  const factorypools = Object.keys(addresses.curve.pools.factory)
    .map((key) => {
      return {
        name: key,
        pool: addresses.curve.pools.factory[key],
      };
    })
    .filter((p) => addresses.curve.pools.gaugeBlacklist.indexOf(p.pool) === -1);
  const cryptofactorypools = Object.keys(addresses.curve.pools.cryptofactory)
    .map((key) => {
      return {
        name: key,
        pool: addresses.curve.pools.cryptofactory[key],
      };
    })
    .filter((p) => addresses.curve.pools.gaugeBlacklist.indexOf(p.pool) === -1);

  beforeEach(async () => {
    ({
      curvePoolIntegration,
      curveMetaRegistry,
      curveGaugeIntegration,
      signer1,
      signer2,
      signer3,
    } = await setupTests()());
  });

  describe('Curve Gauge Multigarden multiasset', function () {
    pick([
      { token: addresses.tokens.WETH, name: 'WETH' },
      { token: addresses.tokens.DAI, name: 'DAI' },
      { token: addresses.tokens.USDC, name: 'USDC' },
      { token: addresses.tokens.WBTC, name: 'WBTC' },
    ]).forEach(async ({ token, name }) => {
      pick(pools).forEach(({ pool, name }) => {
        it(`can enter ${name} CRV pool and stake into gauge`, async function () {
          await depositAndStakeStrategy(pool, token);
        });
      });
      pick(cryptopools).forEach(({ pool, name }) => {
        it(`can enter ${name} CRV pool and stake into gauge`, async function () {
          await depositAndStakeStrategy(pool, token);
        });
      });

      pick(factorypools.concat(cryptofactorypools)).forEach(({ pool, name }) => {
        it(`can enter ${name} CRV pool and stake into gauge`, async function () {
          await depositAndStakeStrategy(pool, token);
        });
      });
    });
    it(`cannot enter an invalid pool`, async function () {
      await expect(tryDepositAndStakeStrategy(ADDRESS_ZERO, addresses.tokens.WETH)).to.be.reverted;
    });
  });

  async function depositAndStakeStrategy(crvpool, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    const gardenReserveAsset = await getERC20(token);
    await depositFunds(token, garden);
    const crvLpToken = await getERC20(await curveMetaRegistry.getLpToken(crvpool));
    const gauge = await getERC20(await curveMetaRegistry.getGauge(crvpool));

    const strategyContract = await createStrategy(
      'lpStack',
      'vote',
      [signer1, signer2, signer3],
      [curvePoolIntegration.address, curveGaugeIntegration.address],
      garden,
      false,
      [crvpool, 0, crvpool, 0],
    );
    const amount = STRATEGY_EXECUTE_MAP[token];
    const balanceBeforeExecuting = await gardenReserveAsset.balanceOf(garden.address);
    await executeStrategy(strategyContract, { amount });
    // Check NAV
    const nav = await strategyContract.getNAV();
    expect(nav).to.be.gte(amount.sub(amount.div(10)));

    expect(await crvLpToken.balanceOf(strategyContract.address)).to.equal(0);
    expect(await gauge.balanceOf(strategyContract.address)).to.be.gt(0);

    // Check reward after a week
    await increaseTime(ONE_DAY_IN_SECONDS * 7);

    const balanceBeforeExiting = await gardenReserveAsset.balanceOf(garden.address);
    await finalizeStrategy(strategyContract, { gasLimit: 99900000 });

    expect(await crvLpToken.balanceOf(strategyContract.address)).to.equal(0);
    expect(await gauge.balanceOf(strategyContract.address)).to.equal(0);

    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.gte(balanceBeforeExiting);
    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.gte(
      balanceBeforeExecuting.sub(balanceBeforeExecuting.div(10)),
    );
  }

  async function tryDepositAndStakeStrategy(crvpool, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    await depositFunds(token, garden);

    const strategyContract = await createStrategy(
      'lpStack',
      'vote',
      [signer1, signer2, signer3],
      [curvePoolIntegration.address, curveGaugeIntegration.address],
      garden,
      false,
      [crvpool, 0, crvpool, 0],
    );
    await expect(executeStrategy(strategyContract, { amount: STRATEGY_EXECUTE_MAP[token] })).to.be.reverted;
  }
});
