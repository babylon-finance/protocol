const { expect } = require('chai');
const { ethers } = require('hardhat');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  getStrategy,
  executeStrategy,
  finalizeStrategy,
} = require('../fixtures/StrategyHelper');
const { parse, from, eth, normalizeDecimals } = require('../utils/test-helpers');
const { setupTests } = require('../fixtures/GardenFixture');
const { createGarden, transferFunds } = require('../fixtures/GardenHelper');
const addresses = require('../../lib/addresses');
const { ADDRESS_ZERO, ONE_ETH, STRATEGY_EXECUTE_MAP } = require('../../lib/constants');

const vaults = [
  '0xFE09e53A81Fe2808bc493ea64319109B5bAa573e',
  '0xab7FA2B2985BCcfC13c6D86b1D5A17486ab1e04C',
  '0x7674622c63Bee7F46E86a4A5A18976693D54441b',
  '0x053c80eA73Dc6941F518a68E2FC52Ac45BDE7c9C',
  '0xf0358e8c3CD5Fa238a29301d0bEa3D63A17bEdBE',
  '0x683E683fBE6Cf9b635539712c999f3B3EdCB8664',
  '0x4b1cBD6F6D8676AcE5E412C78B7a59b4A1bbb68a',
  '0x998cEb152A42a3EaC1f555B1E911642BeBf00faD',
  '0x71B9eC42bB3CB40F017D8AD8011BE8e384a95fa5',
  '0x0FE4283e0216F94f5f9750a7a11AC54D3c9C38F3',
  '0x29780C39164Ebbd62e9DDDE50c151810070140f2',
  '0xCC775989e76ab386E9253df5B0c0b473E22102E2',
  '0x640704D106E79e105FDA424f05467F005418F1B5',
  '0x9aA8F427A17d6B0d91B6262989EdC7D45d6aEdf8',
  '0x5d9d25c7C457dD82fc8668FFC6B9746b674d4EcB',
  '0xC391d1b08c1403313B0c28D47202DFDA015633C4',
  '0x203E97aa6eB65A1A02d9E80083414058303f241E',
  '0x01bd09A1124960d9bE04b638b142Df9DF942b04a',
  '0x64035b583c8c694627A199243E863Bb33be60745',
  '0x5C0A3F55AAC52AA320Ff5F280E77517cbAF85524',
  '0xF553E1f826f42716cDFe02bde5ee76b2a52fc7EB',
  '0x307E2752e8b8a9C29005001Be66B1c012CA9CDB7',
  '0xA79a083FDD87F73c2f983c5551EC974685D6bb36',
  '0x7DDc3ffF0612E75Ea5ddC0d6Bd4e268f70362Cff',
  '0x01112a60f427205dcA6E229425306923c3Cc2073',
  '0x2a32dcBB121D48C106F6d94cf2B4714c0b4Dfe48',
];

describe('HarvestVaultIntegrationTest', function () {
  let harvestVaultIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let daiVault;
  let owner;
  let priceOracle;

  beforeEach(async () => {
    ({ priceOracle, owner, garden1, harvestVaultIntegration, signer1, signer2, signer3 } = await setupTests()());
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
      expect(await harvestVaultIntegration.getPricePerShare(daiVault.address)).to.equal('1040689410052141025');
    });
  });

  describe('getExpectedShares', function () {
    it('get expected shares', async function () {
      expect(await harvestVaultIntegration.getExpectedShares(daiVault.address, ONE_ETH)).to.equal('960901485439250901');
    });
  });
  describe('getInvestmentAsset', function () {
    it('get investment asset', async function () {
      expect(await harvestVaultIntegration.getInvestmentAsset(daiVault.address)).to.equal(addresses.tokens.DAI);
    });
  });
  describe('enter and exit calldata per Garden per Vault', function () {
    [
      { token: addresses.tokens.WETH, name: 'WETH' },
      { token: addresses.tokens.DAI, name: 'DAI' },
      { token: addresses.tokens.USDC, name: 'USDC' },
      { token: addresses.tokens.WBTC, name: 'WBTC' },
    ].forEach(({ token, name }) => {
      [
        { vault: '0xFE09e53A81Fe2808bc493ea64319109B5bAa573e', symbol: 'vWETH' }, //vWETH vault
        { vault: '0xf0358e8c3CD5Fa238a29301d0bEa3D63A17bEdBE', symbol: 'vUSDC' }, //vUSDC vault
        { vault: '0x5d9d25c7C457dD82fc8668FFC6B9746b674d4EcB', symbol: 'vWBTC' }, //vWBTC vault
        { vault: '0xab7FA2B2985BCcfC13c6D86b1D5A17486ab1e04C', symbol: 'vDAI' }, //vDAI vault
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
            specificParams: vault,
          });

          expect(await vaultContract.balanceOf(strategyContract.address)).to.equal(0);

          let amount = STRATEGY_EXECUTE_MAP[token];
          await executeStrategy(strategyContract, { amount });

          const asset = await harvestVaultIntegration.getInvestmentAsset(vault); // USDC, DAI, USDT and etc...
          const assetContract = await ethers.getContractAt('ERC20', asset);
          const assetDecimals = await assetContract.decimals();

          const tokenContract = await ethers.getContractAt('ERC20', token);
          const tokenDecimals = await tokenContract.decimals();

          const reservePriceInAsset = await priceOracle.connect(owner).getPrice(token, asset);

          let conversionRate = eth(1);

          amount = await normalizeDecimals(tokenDecimals, assetDecimals, amount);

          let expectedShares = await harvestVaultIntegration.getExpectedShares(
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
