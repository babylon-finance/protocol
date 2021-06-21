const { expect } = require('chai');
const { ethers } = require('hardhat');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  getStrategy,
  executeStrategy,
  finalizeStrategy,
  injectFakeProfits,
} = require('../fixtures/StrategyHelper');
const { parse, from, eth } = require('../utils/test-helpers');
const { createGarden, transferFunds } = require('../fixtures/GardenHelper');
const { setupTests } = require('../fixtures/GardenFixture');
const addresses = require('../../lib/addresses');
const { ADDRESS_ZERO, ONE_ETH, STRATEGY_EXECUTE_MAP } = require('../../lib/constants');

describe('YearnVaultIntegrationTest', function () {
  let yearnVaultIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let babController;
  let priceOracle;
  let owner;

  async function normalizeDecimals(tokenDecimals, tokenDecimalsTarget, quantity) {
    if (tokenDecimals == tokenDecimalsTarget) {
      return quantity;
    }
    if (tokenDecimalsTarget > tokenDecimals) {
      return quantity.mul(10 ** (tokenDecimalsTarget - tokenDecimals));
    }
    return quantity.div(10 ** (tokenDecimals - tokenDecimalsTarget));
  }

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

    describe('enter and exit calldata per Garden per Vault', function () {
      [
        { token: addresses.tokens.WETH, name: 'WETH' },
        { token: addresses.tokens.DAI, name: 'DAI' },
        { token: addresses.tokens.USDC, name: 'USDC' },
        { token: addresses.tokens.WBTC, name: 'WBTC' },
      ].forEach(({ token, name }) => {
        [
          { vault: '0xa9fE4601811213c340e850ea305481afF02f5b28', symbol: 'yvWETH' }, //yvWETH vault
          { vault: '0x7Da96a3891Add058AdA2E826306D812C638D87a7', symbol: 'yvUSDT' }, //yvUSDT vault
          { vault: '0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9', symbol: 'yvUSDC' }, //yvUSDC vault
          { vault: '0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E', symbol: 'yvWBTC' }, //yvWBTC vault
          { vault: '0x19D3364A399d251E894aC732651be8B0E4e85001', symbol: 'yvDAI' }, //yvDAI vault
        ].forEach(({ vault, symbol }) => {
          it(`can enter and exit the ${symbol} from a ${name} garden`, async function () {
            const vaultContract = await ethers.getContractAt('IYearnVault', vault);
            await transferFunds(token);

            const garden = await createGarden({ reserveAsset: token });
            const strategyContract = await getStrategy({
              kind: 'vault',
              state: 'vote',
              integrations: yearnVaultIntegration.address,
              garden,
              specificParams: vault,
            });

            expect(await vaultContract.balanceOf(strategyContract.address)).to.equal(0);

            let amount = STRATEGY_EXECUTE_MAP[token];
            await executeStrategy(strategyContract, { amount });

            const asset = await yearnVaultIntegration.getInvestmentAsset(vault); // USDC, DAI, USDT and etc...
            const assetContract = await ethers.getContractAt('ERC20', asset);
            const assetDecimals = await assetContract.decimals();

            const tokenContract = await ethers.getContractAt('ERC20', token);
            const tokenDecimals = await tokenContract.decimals();

            const reservePriceInAsset = await priceOracle.connect(owner).getPrice(token, asset);

            // NOTE: getPrice from Oracle returns 1e18 except when token==asset and they have less than 18 decimals, then it returns the same decimals
            let conversionRate =
              tokenDecimals == assetDecimals && tokenDecimals < 18 && asset == token ? 10 ** tokenDecimals : eth(1);

            amount = await normalizeDecimals(tokenDecimals, assetDecimals, amount);

            let expectedShares = await yearnVaultIntegration.getExpectedShares(
              vault,
              reservePriceInAsset.mul(amount).div(conversionRate),
            );

            expect(await vaultContract.balanceOf(strategyContract.address)).to.be.closeTo(
              expectedShares,
              expectedShares.div(50), // 2% percision
            );

            await finalizeStrategy(strategyContract, 0);
            expect(await vaultContract.balanceOf(strategyContract.address)).to.equal(0);
          });
        });
      });
    });
  });
});
