const { expect } = require('chai');
const { ethers } = require('hardhat');
const { getStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { normalizeDecimals, getERC20, getContract, parse, from, eth, pick } = require('utils/test-helpers');
const { createGarden, transferFunds } = require('fixtures/GardenHelper');
const { setupTests } = require('fixtures/GardenFixture');
const addresses = require('lib/addresses');
const { STRATEGY_EXECUTE_MAP, GARDENS } = require('lib/constants');

describe('YearnVaultIntegrationTest', function () {
  let yearnVaultIntegration;
  let babController;
  let priceOracle;
  let owner;
  let daiVault;

  beforeEach(async () => {
    ({ priceOracle, babController, yearnVaultIntegration, owner } = await setupTests()());
    daiVault = await ethers.getContractAt('IYearnVault', addresses.yearn.daiVault);
  });

  describe('getPricePerShare', function () {
    it('get price per share', async function () {
      expect(await yearnVaultIntegration.getPricePerShare(daiVault.address)).to.be.closeTo(
        '1020368483170848269',
        parse('1020368483170848269').div(10),
      );
    });
  });

  describe('getExpectedShares', function () {
    it('get expected shares', async function () {
      expect(await yearnVaultIntegration.getExpectedShares(daiVault.address, eth())).to.be.closeTo(
        '980038110244691069',
        parse('980038110244691069').div(10),
      );
    });
  });

  describe('getInvestmentAsset', function () {
    it('get investment asset', async function () {
      expect(await yearnVaultIntegration.getInvestmentAsset(daiVault.address)).to.equal(addresses.tokens.DAI);
    });
  });

  describe('enter and exits normal vaults (direct assets)', function () {
    pick(GARDENS).forEach(({ token, name }) => {
      pick(addresses.yearn.vaults.filter((y) => !y.curve)).forEach((yvault) => {
        it(`can enter and exit the ${yvault.name} at Yearn Vault from a ${name} garden`, async function () {
          const vaultContract = await ethers.getContractAt('IYearnVault', yvault.vault);
          await transferFunds(token);

          const garden = await createGarden({ reserveAsset: token });
          const strategyContract = await getStrategy({
            kind: 'vault',
            state: 'vote',
            integrations: yearnVaultIntegration.address,
            garden,
            specificParams: [yvault.vault, 0],
          });

          expect(await vaultContract.balanceOf(strategyContract.address)).to.equal(0);

          let amount = STRATEGY_EXECUTE_MAP[token];
          await executeStrategy(strategyContract, { amount });
          // Check NAV
          expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(10));

          const asset = await yearnVaultIntegration.getInvestmentAsset(yvault.vault); // USDC, DAI, USDT and etc...
          const assetContract = await getERC20(asset);
          const assetDecimals = await assetContract.decimals();

          const tokenContract = await getERC20(token);
          const tokenDecimals = await tokenContract.decimals();

          const reservePriceInAsset = await priceOracle.connect(owner).getPrice(token, asset);

          const conversionRate = eth(1);

          amount = await normalizeDecimals(tokenDecimals, assetDecimals, amount);

          const expectedShares = await yearnVaultIntegration.getExpectedShares(
            yvault.vault,
            reservePriceInAsset.mul(amount).div(conversionRate),
          );
          const executionTokenBalance = await tokenContract.balanceOf(garden.address);
          expect(await vaultContract.balanceOf(strategyContract.address)).to.be.closeTo(
            expectedShares,
            expectedShares.div(33), // 3% precision
          );

          await finalizeStrategy(strategyContract, 0);
          expect(await vaultContract.balanceOf(strategyContract.address)).to.equal(0);
          expect(await tokenContract.balanceOf(garden.address)).to.be.gt(executionTokenBalance);
        });
      });
    });
  });
});
