const { expect } = require('chai');
const { ethers } = require('hardhat');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  executeStrategy,
  finalizeStrategy,
} = require('../fixtures/StrategyHelper');
const { setupTests } = require('../fixtures/GardenFixture');
const addresses = require('../../lib/addresses');
const { ADDRESS_ZERO, ONE_ETH } = require('../../lib/constants');

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

  describe('isInvestment', function () {
    vaults.forEach((vault) => {
      it(`check that ${vault} is a valid vault`, async function () {
        expect(await harvestVaultIntegration.isInvestment(vault)).to.equal(true);
      });
    });

    it('check that a vault is NOT valid', async function () {
      await expect(harvestVaultIntegration.isInvestment(ADDRESS_ZERO)).to.be.revertedWith(/non-contract account/);
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

  describe('enter and exit calldata', function () {
    [
      '0xFE09e53A81Fe2808bc493ea64319109B5bAa573e', // WETH
      '0xab7FA2B2985BCcfC13c6D86b1D5A17486ab1e04C', // DAI
      '0xf0358e8c3CD5Fa238a29301d0bEa3D63A17bEdBE', // USDC
      '0x5d9d25c7C457dD82fc8668FFC6B9746b674d4EcB', // WBTC
    ].forEach((vault) => {
      // other vaults fail due to `revert Price not found` error due to some assets being not tradable like LP tokens
      it(`can enter and exit the ${vault} vault`, async function () {
        const vaultContract = await ethers.getContractAt('IHarvestVault', vault);
        const strategyContract = await createStrategy(
          'vault',
          'vote',
          [signer1, signer2, signer3],
          harvestVaultIntegration.address,
          garden1,
          DEFAULT_STRATEGY_PARAMS,
          vault,
        );

        expect(await vaultContract.balanceOf(strategyContract.address)).to.equal(0);

        await executeStrategy(strategyContract);

        const asset = await harvestVaultIntegration.getInvestmentAsset(vault);
        const assetContract = await ethers.getContractAt('ERC20', asset);
        const assetDecimals = await assetContract.decimals();
        const decimalsDelta = 10 ** (18 - assetDecimals);
        const wethPriceInAsset = (await priceOracle.connect(owner).getPrice(addresses.tokens.WETH, asset)).div(
          decimalsDelta,
        );

        const expectedShares = (await harvestVaultIntegration.getExpectedShares(vault, wethPriceInAsset)).div(
          decimalsDelta,
        );
        expect(await vaultContract.balanceOf(strategyContract.address)).to.be.closeTo(
          expectedShares,
          expectedShares.div(50),
        ); // roughly ONE ETH in fAsset

        await finalizeStrategy(strategyContract, 0);

        expect(await vaultContract.balanceOf(strategyContract.address)).to.equal(0);
      });
    });
  });
});
