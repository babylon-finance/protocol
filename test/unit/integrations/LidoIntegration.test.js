const { expect } = require('chai');
const { ethers } = require('hardhat');
const { getStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { createGarden, transferFunds } = require('fixtures/GardenHelper');
const { setupTests } = require('fixtures/GardenFixture');
const addresses = require('lib/addresses');
const { ADDRESS_ZERO, STRATEGY_EXECUTE_MAP, GARDENS } = require('lib/constants');
const { getERC20, getContract, parse, from, eth, pick } = require('utils/test-helpers');

describe('LidoIntegrationTest', function () {
  let lidoIntegration;
  let babController;
  let stETH;
  let wstETH;

  beforeEach(async () => {
    ({ babController, lidoIntegration } = await setupTests()());
    stETH = await ethers.getContractAt('IStETH', addresses.lido.steth);
    wstETH = await ethers.getContractAt('IWstETH', addresses.lido.wsteth);
  });

  describe('Lido Staking', function () {
    describe('getPricePerShare', function () {
      it('gets price per share', async function () {
        const stPrice = await stETH.getPooledEthByShares(eth());
        expect(await lidoIntegration.getPricePerShare(stETH.address)).to.equal(stPrice);
        expect(await lidoIntegration.getPricePerShare(wstETH.address)).to.equal(await wstETH.getStETHByWstETH(stPrice));
      });
    });

    describe('getExpectedShares', function () {
      it('get expected shares', async function () {
        const stShares = await stETH.getSharesByPooledEth(eth());
        expect(await lidoIntegration.getExpectedShares(stETH.address, eth())).to.equal(stShares);
        expect(await lidoIntegration.getExpectedShares(wstETH.address, eth())).to.equal(
          await wstETH.getWstETHByStETH(stShares),
        );
      });
    });

    describe('getInvestmentAsset', function () {
      it('get investment asset', async function () {
        expect(await lidoIntegration.getInvestmentAsset(stETH.address)).to.equal(ADDRESS_ZERO);
        expect(await lidoIntegration.getInvestmentAsset(wstETH.address)).to.equal(ADDRESS_ZERO);
      });
    });

    describe('enter and exit operation with both assets', function () {
      pick(GARDENS).forEach(({ token, name }) => {
        [
          { target: addresses.lido.steth, symbol: 'stETH' }, // stETH
          { target: addresses.lido.wsteth, symbol: 'wstETH' }, // wstETH
        ].forEach(({ target, symbol }) => {
          it(`can enter and exit the ${symbol} staking from a ${name} garden`, async function () {
            const targetContract = await ethers.getContractAt(
              target === addresses.lido.steth ? 'IStETH' : 'IWstETH',
              target,
            );
            await transferFunds(token);

            const garden = await createGarden({ reserveAsset: token });
            const strategyContract = await getStrategy({
              kind: 'vault',
              state: 'vote',
              integrations: lidoIntegration.address,
              garden,
              specificParams: [target, 0],
            });

            expect(await targetContract.balanceOf(strategyContract.address)).to.equal(0);
            const reserveContract = await getERC20(token);
            const amount = STRATEGY_EXECUTE_MAP[token];
            await executeStrategy(strategyContract, { amount });
            // Check NAV
            expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(20));

            const beforeBalance = await reserveContract.balanceOf(garden.address);
            expect(await targetContract.balanceOf(strategyContract.address)).to.be.gt(0);
            await finalizeStrategy(strategyContract, 0);
            const newBalance = await targetContract.balanceOf(strategyContract.address);
            expect(newBalance).to.be.lt(1000);
            expect(await reserveContract.balanceOf(garden.address)).to.be.gt(beforeBalance);
          });
        });
      });
    });
  });
});
