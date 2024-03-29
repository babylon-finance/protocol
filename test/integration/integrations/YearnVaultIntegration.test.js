const { expect } = require('chai');
const { ethers } = require('hardhat');
const { getStrategy, createStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { normalizeDecimals, getERC20, getContract, parse, from, eth, pick } = require('utils/test-helpers');
const { createGarden, transferFunds } = require('fixtures/GardenHelper');
const { setupTests } = require('fixtures/GardenFixture');
const addresses = require('lib/addresses');
const { STRATEGY_EXECUTE_MAP, GARDENS } = require('lib/constants');

describe('YearnVaultIntegrationTest', function () {
  let yearnVaultIntegration;
  let curvePoolIntegration;
  let priceOracle;
  let curveMetaRegistry;
  let owner;
  let daiVault;
  let signer1;
  let signer2;
  let signer3;

  beforeEach(async () => {
    ({
      priceOracle,
      curvePoolIntegration,
      yearnVaultIntegration,
      curveMetaRegistry,
      owner,
      signer1,
      signer2,
      signer3,
    } = await setupTests()());
    daiVault = await ethers.getContractAt('IYearnVault', addresses.yearn.daiVault);
  });

  // Used to create addresses info. do not remove
  async function logYearnVaults() {
    await Promise.all(
      addresses.yearn.vaults.map(async (vault) => {
        return await logYearnVaultUnderlying(vault);
      }),
    );
  }

  async function logYearnVaultUnderlying(vault) {
    const yvault = await ethers.getContractAt('IYearnVault', vault.vault);
    vault.needs = await yvault.token();
    if (vault.curve) {
      vault.crvpool = await curveMetaRegistry.getPoolFromLpToken(vault.needs);
    }
    // console.log(JSON.stringify(vault), ',');
  }

  describe('logs vaults', function () {
    it.skip('logs all vaults', async function () {
      await logYearnVaults();
    });
  });

  describe('getInvestmentAsset', function () {
    it('get investment asset', async function () {
      expect(await yearnVaultIntegration.getInvestmentAsset(daiVault.address)).to.equal(addresses.tokens.DAI);
    });
  });

  const testVault = async (yvault, token, name, crvpool) => {
    const vaultContract = await ethers.getContractAt('IYearnVault', yvault.vault);
    await transferFunds(token);

    const garden = await createGarden({ reserveAsset: token });
    let strategyContract;
    if (crvpool) {
      strategyContract = await createStrategy(
        'lpStack',
        'vote',
        [signer1, signer2, signer3],
        [curvePoolIntegration.address, yearnVaultIntegration.address],
        garden,
        false,
        [crvpool, 0, yvault.vault, 0],
      );
    } else {
      strategyContract = await getStrategy({
        kind: 'vault',
        state: 'vote',
        integrations: yearnVaultIntegration.address,
        garden,
        specificParams: [yvault.vault, 0],
      });
    }

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
    amount = await normalizeDecimals(tokenDecimals, assetDecimals, amount);
    const executionTokenBalance = await tokenContract.balanceOf(garden.address);
    expect(await vaultContract.balanceOf(strategyContract.address)).to.be.gt(0);
    await finalizeStrategy(strategyContract, 0);
    expect(await vaultContract.balanceOf(strategyContract.address)).to.equal(0);
    expect(await tokenContract.balanceOf(garden.address)).to.be.gt(executionTokenBalance);
  };

  describe('enter and exits normal vaults (direct assets)', function () {
    pick(GARDENS).forEach(({ token, name }) => {
      pick(addresses.yearn.vaults.filter((y) => !y.curve && !y.skipTest)).forEach((yvault) => {
        it(`can enter and exit the ${yvault.name} at Yearn Vault from a ${name} garden`, async function () {
          await testVault(yvault, token, name);
        });
      });
    });
  });
  describe('enter and exits curve vaults', function () {
    pick(GARDENS).forEach(({ token, name }) => {
      pick(
        addresses.yearn.vaults.filter(
          (y) => y.curve && y.crvpool !== '0x0000000000000000000000000000000000000000' && !y.skipTest,
        ),
      ).forEach((yvault) => {
        it(`can enter and exit the ${yvault.name} at Yearn Vault from a ${name} garden`, async function () {
          await testVault(yvault, token, name, yvault.crvpool);
        });
      });
    });
  });
});
