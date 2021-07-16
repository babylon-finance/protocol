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
  let priceOracle;
  let owner;

  beforeEach(async () => {
    ({ priceOracle, babController, lidoIntegration, owner } = await setupTests()());
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      const deployedYearn = await lidoIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedYearn).to.equal(true);
    });
  });

  describe('Lido Staking', function () {
    let stETH;
    let wstETH;

    beforeEach(async () => {
      stETH = await ethers.getContractAt('IStETH', addresses.yearn.lido.steth);
      wstETH = await ethers.getContractAt('IWstETH', addresses.yearn.lido.wsteth);
    });

    describe('getPricePerShare', function () {
      it('get price per share', async function () {
        expect(await lidoIntegration.getPricePerShare(stETH.address)).to.equal('1053972283161872856');
        expect(await lidoIntegration.getPricePerShare(wstETH.address)).to.equal('1053972283161872856');
      });
    });

    describe('getExpectedShares', function () {
      it('get expected shares', async function () {
        expect(await lidoIntegration.getExpectedShares(stETH.address, ONE_ETH)).to.equal('948791553607123083');
        expect(await lidoIntegration.getExpectedShares(wstETH.address, ONE_ETH)).to.equal('948791553607123083');
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
          { target: stETH.address, symbol: 'stETH' }, // stETH
          { target: wstETH, symbol: 'wstETH' }, // wstETH
        ].forEach(({ target, symbol }) => {
          it(`can enter and exit the ${symbol} at Yearn Vault from a ${name} garden`, async function () {
            const targetContract = await ethers.getContractAt('IYearnVault', target);
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

            const amount = STRATEGY_EXECUTE_MAP[token];
            await executeStrategy(strategyContract, { amount });
            // Check NAV
            expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(50));

            const reservePriceInAsset = await priceOracle.connect(owner).getPrice(token, addresses.tokens.WETH);
            const expectedShares = await lidoIntegration.getExpectedShares(target, reservePriceInAsset);
            const reserveContract = await ethers.getContractAt('ERC20', token);
            const beforeBalance = await reserveContract.balanceOf(garden.address);
            expect(await targetContract.balanceOf(strategyContract.address)).to.be.closeTo(
              expectedShares,
              expectedShares.div(50), // 2% percision
            );

            await finalizeStrategy(strategyContract, 0);
            expect(await targetContract.balanceOf(strategyContract.address)).to.equal(0);
            expect(await reserveContract.balanceOf(garden.address)).to.be.gt(beforeBalance);
          });
        });
      });
    });
  });
});
