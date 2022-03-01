const { expect } = require('chai');
const { getStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { createGarden, transferFunds } = require('fixtures/GardenHelper');
const { setupTests } = require('fixtures/GardenFixture');
const addresses = require('lib/addresses');
const { STRATEGY_EXECUTE_MAP, GARDENS } = require('lib/constants');
const { getERC20, eth, pick } = require('utils/test-helpers');

describe('PaladinTradeIntegrationTest', function () {
  let masterSwapper;
  let palStkAAVE;

  beforeEach(async () => {
    ({ masterSwapper } = await setupTests()());
    palStkAAVE = await getERC20(addresses.paladin.palStkAAVE);
  });

  describe('Paladin Trade', function () {
    describe('enter and exit operation', function () {
      pick([...GARDENS]).forEach(({ token, name }) => {
        it(`can get palStkAAVE from a ${name} garden`, async function () {
          await transferFunds(token);
          const garden = await createGarden({ reserveAsset: token });
          const assetContract = await getERC20(addresses.tokens.AAVE);

          const strategyContract = await getStrategy({
            kind: 'buy',
            state: 'vote',
            integration: masterSwapper.address,
            specificParams: [palStkAAVE.address, 0],
            garden,
          });

          expect(await palStkAAVE.balanceOf(strategyContract.address)).to.equal(0);
          const reserveContract = await getERC20(token);
          const amount = STRATEGY_EXECUTE_MAP[token];
          await executeStrategy(strategyContract, { amount });
          // Check NAV
          expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(15));
          const beforeBalance = await reserveContract.balanceOf(garden.address);
          expect(await palStkAAVE.balanceOf(strategyContract.address)).to.be.gt(0);
          await finalizeStrategy(strategyContract, 0);
          expect(0).to.eq(await assetContract.balanceOf(strategyContract.address));
          const newBalance = await palStkAAVE.balanceOf(strategyContract.address);
          expect(newBalance).to.be.lt(eth().div(100));
          expect(await reserveContract.balanceOf(garden.address)).to.be.gt(beforeBalance);
        });
      });
    });
  });
});
