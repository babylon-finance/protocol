const { expect } = require('chai');
const { ethers } = require('hardhat');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  executeStrategy,
  finalizeStrategy,
} = require('../fixtures/StrategyHelper');
const { parse, from } = require('../utils/test-helpers');
const { setupTests } = require('../fixtures/GardenFixture');
const addresses = require('../../lib/addresses');
const { ADDRESS_ZERO, ONE_ETH } = require('../../lib/constants');

describe('YearnVaultIntegrationTest', function () {
  let yearnVaultIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let babController;
  let priceOracle;
  let owner;

  beforeEach(async () => {
    ({
      garden1,
      priceOracle,
      babController,
      yearnVaultIntegration,
      owner,
      signer1,
      signer2,
      signer3,
    } = await setupTests()());
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      const deployedYearn = await yearnVaultIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedYearn).to.equal(true);
    });
  });

  describe('Yearn Vaults', function () {
    let daiToken;
    let daiVault;
    let WETH;

    beforeEach(async () => {
      daiToken = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
      daiVault = await ethers.getContractAt('IYearnVault', addresses.yearn.vaults.ydai);
      WETH = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
    });

    describe('getPricePerShare', function () {
      it('get price per share', async function () {
        expect(await yearnVaultIntegration.getPricePerShare(daiVault.address)).to.equal('1042373373038108666');
      });
    });

    describe('getExpectedShares', function () {
      it('get expected shares', async function () {
        expect(await yearnVaultIntegration.getExpectedShares(daiVault.address, ONE_ETH)).to.equal('959349140975649695');
      });
    });

    describe('getInvestmentAsset', function () {
      it('get investment asset', async function () {
        expect(await yearnVaultIntegration.getInvestmentAsset(daiVault.address)).to.equal(addresses.tokens.DAI);
      });
    });

    describe('enter and exit calldata', function () {
      [
        '0x19D3364A399d251E894aC732651be8B0E4e85001', // yvDAI
        '0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9', // yvUSDC
        '0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E', // yvWBTC
        '0xa9fE4601811213c340e850ea305481afF02f5b28', // yvWETH
        '0x7Da96a3891Add058AdA2E826306D812C638D87a7', // yvUSDT
      ].forEach((vault) => {
        // other vaults fail due to `revert Price not found` error due to some assets being not tradable like LP tokens
        it(`can enter and exit the ${vault} vault`, async function () {
          const vaultContract = await ethers.getContractAt('IYearnVault', vault);
          const strategyContract = await createStrategy(
            'vault',
            'vote',
            [signer1, signer2, signer3],
            yearnVaultIntegration.address,
            garden1,
            DEFAULT_STRATEGY_PARAMS,
            vault,
          );

          expect(await vaultContract.balanceOf(strategyContract.address)).to.equal(0);

          await executeStrategy(strategyContract);

          const asset = await yearnVaultIntegration.getInvestmentAsset(vault);
          const assetContract = await ethers.getContractAt('ERC20', asset);
          const assetDecimals = await assetContract.decimals();
          const decimalsDelta = 10 ** (18 - assetDecimals);
          const wethPriceInAsset = (await priceOracle.connect(owner).getPrice(addresses.tokens.WETH, asset)).div(
            decimalsDelta,
          );

          const expectedShares = (await yearnVaultIntegration.getExpectedShares(vault, wethPriceInAsset)).div(
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
});
