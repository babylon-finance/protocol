const { expect } = require('chai');
const { getStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { createGarden, transferFunds } = require('fixtures/GardenHelper');
const { setupTests } = require('fixtures/GardenFixture');
const addresses = require('lib/addresses');
const { STRATEGY_EXECUTE_MAP, GARDENS } = require('lib/constants');
const { getERC20, eth, pick } = require('utils/test-helpers');

describe('PaladinStakeIntegrationTest', function () {
  let paladinStakeIntegration;
  let palStkAAVE;

  beforeEach(async () => {
    ({ paladinStakeIntegration } = await setupTests()());
    palStkAAVE = await getERC20(addresses.paladin.palStkAAVE);
  });

  describe('Paladin Staking', function () {
    describe('getPricePerShare', function () {
      it('gets price per share', async function () {
        expect(await paladinStakeIntegration.getPricePerShare(palStkAAVE.address)).to.equal(eth());
      });
    });

    describe('getExpectedShares', function () {
      it('get expected shares', async function () {
        expect(await paladinStakeIntegration.getExpectedShares(palStkAAVE.address, eth())).to.equal(eth());
      });
    });

    describe('getInvestmentAsset', function () {
      it('get investment asset', async function () {
        expect((await paladinStakeIntegration.getInvestmentAsset(palStkAAVE.address)).toLowerCase()).to.equal(
          addresses.tokens.AAVE.toLowerCase(),
        );
      });
    });

    describe('enter and exit operation', function () {
      pick([...GARDENS, { token: addresses.tokens.AAVE, name: 'AAVE' }]).forEach(({ token, name }) => {
        it(`can enter and exit palStkAAVE staking from a ${name} garden`, async function () {
          await transferFunds(token);
          const garden = await createGarden({ reserveAsset: token });
          const strategyContract = await getStrategy({
            kind: 'vault',
            state: 'vote',
            integrations: paladinStakeIntegration.address,
            garden,
            specificParams: [addresses.paladin.palStkAAVE, 0],
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
          const newBalance = await palStkAAVE.balanceOf(strategyContract.address);
          expect(newBalance).to.be.lt(eth().div(100));
          expect(await reserveContract.balanceOf(garden.address)).to.be.gt(beforeBalance);
        });
      });
    });
  });
});
