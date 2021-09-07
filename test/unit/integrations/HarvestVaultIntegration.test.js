const { expect } = require('chai');
const { ethers } = require('hardhat');
const { getStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { eth, normalizeDecimals } = require('utils/test-helpers');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { ONE_ETH, STRATEGY_EXECUTE_MAP } = require('lib/constants');

describe('HarvestVaultIntegrationTest', function () {
  let harvestVaultIntegration;
  let daiVault;
  let owner;
  let priceOracle;

  beforeEach(async () => {
    ({ priceOracle, owner, harvestVaultIntegration } = await setupTests()());
    daiVault = await ethers.getContractAt('IHarvestVault', addresses.harvest.vaults.fDAI);
  });

  describe('deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await harvestVaultIntegration.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe('getPricePerShare', function () {
    it('get price per share', async function () {
      expect(await harvestVaultIntegration.getPricePerShare(daiVault.address)).to.equal('1054750458858720348');
    });
  });

  describe('getExpectedShares', function () {
    it('get expected shares', async function () {
      expect(await harvestVaultIntegration.getExpectedShares(daiVault.address, ONE_ETH)).to.equal('948091552462596315');
    });
  });
  describe('getInvestmentAsset', function () {
    it('get investment asset', async function () {
      expect(await harvestVaultIntegration.getInvestmentAsset(daiVault.address)).to.equal(addresses.tokens.DAI);
    });
  });
  // TODO - get test back when they are not greylisted by Harvest
  describe.skip('enter and exit calldata per Garden per Vault', function () {
    [
      { token: addresses.tokens.WETH, name: 'WETH' },
      { token: addresses.tokens.DAI, name: 'DAI' },
      { token: addresses.tokens.USDC, name: 'USDC' },
      { token: addresses.tokens.WBTC, name: 'WBTC' },
    ].forEach(({ token, name }) => {
      [
        { vault: '0xFE09e53A81Fe2808bc493ea64319109B5bAa573e', symbol: 'vWETH' }, // vWETH vault
        { vault: '0xf0358e8c3CD5Fa238a29301d0bEa3D63A17bEdBE', symbol: 'vUSDC' }, // vUSDC vault
        { vault: '0x5d9d25c7C457dD82fc8668FFC6B9746b674d4EcB', symbol: 'vWBTC' }, // vWBTC vault
        { vault: '0xab7FA2B2985BCcfC13c6D86b1D5A17486ab1e04C', symbol: 'vDAI' }, // vDAI vault
      ].forEach(({ vault, symbol }) => {
        it(`can enter and exit the ${symbol} at Harvest Vault from a ${name} garden`, async function () {
          const vaultContract = await ethers.getContractAt('IHarvestVault', vault);
          await transferFunds(token);

          const garden = await createGarden({ reserveAsset: token });
          const strategyContract = await getStrategy({
            kind: 'vault',
            state: 'vote',
            integrations: harvestVaultIntegration.address,
            garden,
            specificParams: [vault, 0],
          });

          expect(await vaultContract.balanceOf(strategyContract.address)).to.equal(0);

          let amount = STRATEGY_EXECUTE_MAP[token];
          await executeStrategy(strategyContract, { amount });
          // Check NAV
          expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(50));

          const asset = await harvestVaultIntegration.getInvestmentAsset(vault); // USDC, DAI, USDT and etc...
          const assetContract = await ethers.getContractAt(
            '@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20',
            asset,
          );
          const assetDecimals = await assetContract.decimals();

          const tokenContract = await ethers.getContractAt('ERC20', token);
          const tokenDecimals = await tokenContract.decimals();

          const reservePriceInAsset = await priceOracle.connect(owner).getPrice(token, asset);

          const conversionRate = eth(1);

          amount = await normalizeDecimals(tokenDecimals, assetDecimals, amount);

          const expectedShares = await harvestVaultIntegration.getExpectedShares(
            vault,
            reservePriceInAsset.mul(amount).div(conversionRate),
          );

          expect(await vaultContract.balanceOf(strategyContract.address)).to.be.closeTo(
            expectedShares,
            expectedShares.div(50), // 2% percision
          );
          const executionTokenBalance = await tokenContract.balanceOf(garden.address);

          await finalizeStrategy(strategyContract, 0);
          expect(await vaultContract.balanceOf(strategyContract.address)).to.equal(0);
          expect(await tokenContract.balanceOf(garden.address)).to.be.gt(executionTokenBalance);
        });
      });
    });
  });
});
