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

  describe('enter and exit calldata per Garden per Vault', function () {
    pick(GARDENS).forEach(({ token, name }) => {
      pick([
        { vault: '0xa258C4606Ca8206D8aA700cE2143D7db854D168c', symbol: 'yvWETH' }, // yvWETH vault // old 0xa9fE4601811213c340e850ea305481afF02f5b28
        { vault: '0x7Da96a3891Add058AdA2E826306D812C638D87a7', symbol: 'yvUSDT' }, // yvUSDT vault
        { vault: '0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9', symbol: 'yvUSDC' }, // yvUSDC vault
        { vault: '0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E', symbol: 'yvWBTC' }, // yvWBTC vault
        { vault: '0xda816459f1ab5631232fe5e97a05bbbb94970c95', symbol: 'yvDAI' }, // yvDAI vault
      ]).forEach(({ vault, symbol }) => {
        it(`can enter and exit the ${symbol} at Yearn Vault from a ${name} garden`, async function () {
          const vaultContract = await ethers.getContractAt('IYearnVault', vault);
          await transferFunds(token);

          const garden = await createGarden({ reserveAsset: token });
          const strategyContract = await getStrategy({
            kind: 'vault',
            state: 'vote',
            integrations: yearnVaultIntegration.address,
            garden,
            specificParams: [vault, 0],
          });

          expect(await vaultContract.balanceOf(strategyContract.address)).to.equal(0);

          let amount = STRATEGY_EXECUTE_MAP[token];
          await executeStrategy(strategyContract, { amount });
          // Check NAV
          expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(10));

          const asset = await yearnVaultIntegration.getInvestmentAsset(vault); // USDC, DAI, USDT and etc...
          const assetContract = await getERC20(asset);
          const assetDecimals = await assetContract.decimals();

          const tokenContract = await getERC20(token);
          const tokenDecimals = await tokenContract.decimals();

          const reservePriceInAsset = await priceOracle.connect(owner).getPrice(token, asset);

          const conversionRate = eth(1);

          amount = await normalizeDecimals(tokenDecimals, assetDecimals, amount);

          const expectedShares = await yearnVaultIntegration.getExpectedShares(
            vault,
            reservePriceInAsset.mul(amount).div(conversionRate),
          );
          const executionTokenBalance = await tokenContract.balanceOf(garden.address);
          expect(await vaultContract.balanceOf(strategyContract.address)).to.be.closeTo(
            expectedShares,
            expectedShares.div(50), // 2% percision
          );

          await finalizeStrategy(strategyContract, 0);
          expect(await vaultContract.balanceOf(strategyContract.address)).to.equal(0);
          expect(await tokenContract.balanceOf(garden.address)).to.be.gt(executionTokenBalance);
        });
      });
    });
  });
});
