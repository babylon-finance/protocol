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
      console.log('EQUAL DECIMALS');
      return quantity;
    }
    if (tokenDecimalsTarget > tokenDecimals) {
      console.log('TARGET MORE DECIMALS', (tokenDecimalsTarget - tokenDecimals).toString());
      return quantity.mul(10**(tokenDecimalsTarget - tokenDecimals));
    }
    console.log('ORIGIN MORE DECIMALS', (tokenDecimals - tokenDecimalsTarget).toString());

    return quantity.div(10**(tokenDecimals - tokenDecimalsTarget));
  }

  async function normalizeExpectedShare(tokenDecimals, tokenDecimalsTarget, expectedShares){
    if (tokenDecimals == tokenDecimalsTarget && tokenDecimals == 6) {
      console.log('EQUAL DECIMALS');
      return expectedShares.div(10**(12)); // preciseDiv behavior 
    }
    if (tokenDecimals == tokenDecimalsTarget) {
      console.log('EQUAL DECIMALS');
      return expectedShares;
    }
    if ((tokenDecimalsTarget - tokenDecimals) >= 10) {
      console.log('TARGET MORE DECIMALS 10-12', (tokenDecimalsTarget - tokenDecimals).toString());
      return expectedShares;
    }
    if ((tokenDecimalsTarget - tokenDecimals) == 2) {
      console.log('TARGET MORE DECIMALS 10-12', (tokenDecimalsTarget - tokenDecimals).toString());
      return expectedShares.div(10**(10));
    }
    if (tokenDecimalsTarget > tokenDecimals) {
      console.log('TARGET MORE DECIMALS', (tokenDecimalsTarget - tokenDecimals).toString());
      return expectedShares.mul(10**(tokenDecimalsTarget - tokenDecimals));
    }
    if ((tokenDecimals - tokenDecimalsTarget) == 2){

      console.log('ORIGIN MORE DECIMALS', (tokenDecimals - tokenDecimalsTarget).toString());
      return expectedShares.div(10**(12));
    }
    console.log('ORIGIN MORE DECIMALS', (tokenDecimals - tokenDecimalsTarget).toString());

    return expectedShares.div(10**(tokenDecimals - tokenDecimalsTarget));
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

    describe.only('enter and exit calldata per Garden per Vault', function () {
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

            const amount = STRATEGY_EXECUTE_MAP[token];
            await executeStrategy(strategyContract, { amount });

            const asset = await yearnVaultIntegration.getInvestmentAsset(vault); // USDC, DAI, USDT and etc...
            const assetContract = await ethers.getContractAt('ERC20', asset);
            const assetDecimals = await assetContract.decimals();

            const tokenContract = await ethers.getContractAt('ERC20', token);
            const tokenDecimals = await tokenContract.decimals();
            console.log('tokenDecimals', tokenDecimals.toString());
            console.log('assetDecimals', assetDecimals.toString());


            const decimalsDelta = 10 ** (tokenDecimals - assetDecimals);
            console.log('decimalsDelta', decimalsDelta.toString());

            let reservePriceInAsset = await priceOracle.connect(owner).getPrice(token, asset);
            console.log('reservePriceInAsset', reservePriceInAsset.toString());
            //reservePriceInAsset =
            // decimalsDelta >= 1 ? reservePriceInAsset.div(decimalsDelta) : reservePriceInAsset.mul(decimalsDelta);
            //reservePriceInAsset = await normalizeDecimals(tokenDecimals, assetDecimals, reservePriceInAsset);
            //console.log('new reservePriceInAsset', reservePriceInAsset.toString());
            
            let quantity = await normalizeDecimals(tokenDecimals, assetDecimals, reservePriceInAsset.mul(amount).div(eth(1)));
            //quantity = await normalizeDecimals(tokenDecimals, assetDecimals, reservePriceInAsset.mul(amount));

            console.log('amount', amount.toString());
            console.log('new amount', quantity.toString());




            let expectedShares = await yearnVaultIntegration.getExpectedShares(
              vault,
              quantity,
            );
            console.log('CHECK expected shares', expectedShares.toString());
            console.log('CHECK vault balance', (await vaultContract.balanceOf(strategyContract.address)).toString());
                  
            expectedShares = await normalizeExpectedShare(tokenDecimals, assetDecimals, expectedShares);
            console.log('expected shares normalized', expectedShares.toString());

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
