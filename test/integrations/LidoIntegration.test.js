const { expect } = require('chai');
const { ethers } = require('hardhat');
const { getStrategy, executeStrategy, finalizeStrategy } = require('../fixtures/StrategyHelper');
const { createGarden, transferFunds } = require('../fixtures/GardenHelper');
const { setupTests } = require('../fixtures/GardenFixture');
const addresses = require('../../lib/addresses');
const { ADDRESS_ZERO, ONE_ETH, STRATEGY_EXECUTE_MAP } = require('../../lib/constants');

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

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      const deployedLido = await lidoIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedLido).to.equal(true);
    });
  });

  describe('Lido Staking', function () {
    describe('getPricePerShare', function () {
      it('get price per share', async function () {
        const stPrice = await stETH.getPooledEthByShares(ONE_ETH);
        expect(await lidoIntegration.getPricePerShare(stETH.address)).to.equal(stPrice);
        expect(await lidoIntegration.getPricePerShare(wstETH.address)).to.equal(await wstETH.getStETHByWstETH(stPrice));
      });
    });

    describe('getExpectedShares', function () {
      it('get expected shares', async function () {
        const stShares = await stETH.getSharesByPooledEth(ONE_ETH);
        expect(await lidoIntegration.getExpectedShares(stETH.address, ONE_ETH)).to.equal(stShares);
        expect(await lidoIntegration.getExpectedShares(wstETH.address, ONE_ETH)).to.equal(
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
      [
        { token: addresses.tokens.WETH, name: 'WETH' },
        { token: addresses.tokens.DAI, name: 'DAI' },
        { token: addresses.tokens.USDC, name: 'USDC' },
        { token: addresses.tokens.WBTC, name: 'WBTC' },
      ].forEach(({ token, name }) => {
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
            const reserveContract = await ethers.getContractAt('ERC20', token);
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
