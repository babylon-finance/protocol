const { expect } = require('chai');
const { getStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { createGarden, transferFunds } = require('fixtures/GardenHelper');
const { setupTests } = require('fixtures/GardenFixture');
const addresses = require('lib/addresses');
const { STRATEGY_EXECUTE_MAP, GARDENS } = require('lib/constants');
const { getERC20, eth, pick, increaseTime } = require('utils/test-helpers');

describe('LidoIntegrationTest', function () {
  let stakewiseIntegration;
  let sETH2;
  let rETH2;

  beforeEach(async () => {
    ({ stakewiseIntegration } = await setupTests()());
    sETH2 = await getERC20(addresses.stakewise.seth2);
    rETH2 = await getERC20(addresses.stakewise.reth2);
  });

  describe('Stakewise Staking', function () {
    describe('getPricePerShare', function () {
      it('gets price per share', async function () {
        expect(await stakewiseIntegration.getPricePerShare(sETH2.address)).to.equal(eth());
        expect(await stakewiseIntegration.getPricePerShare(rETH2.address)).to.equal(eth());
      });
    });

    describe('getExpectedShares', function () {
      it('get expected shares', async function () {
        expect(await stakewiseIntegration.getExpectedShares(sETH2.address, eth())).to.equal(eth());
      });
    });

    describe('getInvestmentAsset', function () {
      it('get investment asset', async function () {
        expect(await stakewiseIntegration.getInvestmentAsset(sETH2.address)).to.equal(addresses.tokens.WETH);
      });
    });

    describe('enter and exit operation', function () {
      pick(GARDENS.slice(0, 1)).forEach(({ token, name }) => {
        it(`can enter and exit sETH2 staking from a ${name} garden`, async function () {
          await transferFunds(token);
          const garden = await createGarden({ reserveAsset: token });
          const strategyContract = await getStrategy({
            kind: 'vault',
            state: 'vote',
            integrations: stakewiseIntegration.address,
            garden,
            specificParams: [addresses.stakewise.seth2, 0],
          });
          expect(await sETH2.balanceOf(strategyContract.address)).to.equal(0);
          expect(await rETH2.balanceOf(strategyContract.address)).to.equal(0);
          const reserveContract = await getERC20(token);
          const amount = STRATEGY_EXECUTE_MAP[token];
          await executeStrategy(strategyContract, { amount });
          await increaseTime(86400 * 20);
          // Check NAV
          expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(15));
          const beforeBalance = await reserveContract.balanceOf(garden.address);
          expect(await sETH2.balanceOf(strategyContract.address)).to.be.closeTo(amount, amount.div(15));
          // expect(await rETH2.balanceOf(strategyContract.address)).to.be.gt(0);
          await finalizeStrategy(strategyContract, 0);
          const newBalance = await sETH2.balanceOf(strategyContract.address);
          expect(newBalance).to.be.lt(eth().div(100));
          expect(await rETH2.balanceOf(strategyContract.address)).to.be.lte(eth().div(50)); // leaves quantities below 0.02
          expect(await reserveContract.balanceOf(garden.address)).to.be.gt(beforeBalance);
        });
      });
    });
  });
});
