const { expect } = require('chai');
const { getStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { impersonateAddress } = require('lib/rpc');
const { createGarden, transferFunds } = require('fixtures/GardenHelper');
const { setupTests } = require('fixtures/GardenFixture');
const addresses = require('lib/addresses');
const { STRATEGY_EXECUTE_MAP, GARDENS } = require('lib/constants');
const { getERC20, eth, pick, increaseTime } = require('utils/test-helpers');

describe('StakewiseIntegrationTest', function () {
  let stakewiseIntegration;
  let sETH2;
  let rETH2;

  beforeEach(async () => {
    ({ stakewiseIntegration } = await setupTests()());
    sETH2 = await getERC20(addresses.stakewise.seth2);
    rETH2 = await getERC20(addresses.stakewise.reth2);
  });

  describe('Stakewise Staking', function () {

    describe('getInvestmentAsset', function () {
      it('get investment asset', async function () {
        expect(await stakewiseIntegration.getInvestmentAsset(sETH2.address)).to.equal(addresses.tokens.WETH);
      });
    });

    describe('enter and exit operation', function () {
      pick(GARDENS).forEach(({ token, name }) => {
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
          expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(15));
          // Add rewards
          const whaleSigner = await impersonateAddress('0xa9ffb27d36901f87f1d0f20773f7072e38c5bfba');
          await rETH2.connect(whaleSigner).transfer(strategyContract.address, eth('0.1'), { gasPrice: 0 });
          const beforeBalance = await reserveContract.balanceOf(garden.address);
          expect(await sETH2.balanceOf(strategyContract.address)).to.be.closeTo(amount, amount.div(15));
          expect(await rETH2.balanceOf(strategyContract.address)).to.be.closeTo(eth('0.1'), eth('0.01'));
          expect(await strategyContract.getNAV()).to.be.gt(amount);
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
