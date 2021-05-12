const { expect } = require('chai');
const { ethers } = require('hardhat');

const addresses = require('../lib/addresses');
const { ONE_ETH } = require('../lib/constants');
const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require('../lib/system.js');
const { setupTests } = require('./fixtures/GardenFixture');

describe('PriceOracle', function () {
  let babController;
  let priceOracle;
  let adapter;
  let univ3;
  let owner;

  beforeEach(async () => {
    ({ babController, priceOracle, owner } = await setupTests()());
    adapter = await ethers.getContractAt('UniswapTWAP', (await priceOracle.getAdapters())[0]);
    univ3 = await ethers.getContractAt('UniswapTWAPV3', (await priceOracle.getAdapters())[1]);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployedc = await babController.deployed();
      const deployed = await priceOracle.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedc).to.equal(true);
    });
  });

  describe('UniswapAnchoredView', function () {
    it('should get the price of ETH/DAI', async function () {
      const price = await priceOracle.connect(owner).getPrice(addresses.tokens.WETH, addresses.tokens.DAI);
      expect(price).to.be.gt(ethers.utils.parseEther('500'));
    });

    it('should get the price of DAI/USDC', async function () {
      const price = await priceOracle.connect(owner).getPrice(addresses.tokens.DAI, addresses.tokens.USDC);
      expect(price).to.be.lt(ethers.utils.parseEther('1.1'));
    });
    it('should get the price of WETH/USDC', async function () {
      const price = await priceOracle.connect(owner).getPrice(addresses.tokens.WETH, addresses.tokens.USDC);
      expect(price).to.be.gt(ethers.utils.parseEther('1.8'));
    });
  });

  describe('Uniswap TWAP', function () {
    it('should not get the price of YFI without enough observations', async function () {
      await adapter.update(addresses.tokens.YFI, addresses.tokens.WETH);
      await expect(adapter.getPrice(addresses.tokens.YFI, addresses.tokens.WETH)).to.be.reverted;
    });

    it('should get the price of YFI with enough observations', async function () {
      for (let i = 0; i < TWAP_ORACLE_GRANULARITY; i += 1) {
        await adapter.update(addresses.tokens.YFI, addresses.tokens.WETH);
        ethers.provider.send('evm_increaseTime', [TWAP_ORACLE_WINDOW / TWAP_ORACLE_GRANULARITY]);
      }
      const { amountOut } = await adapter.getPrice(addresses.tokens.YFI, addresses.tokens.WETH);
      expect(amountOut).to.be.gt(ethers.utils.parseEther('15'));
    });

    it('should get the price of DAI', async function () {
      for (let i = 0; i < TWAP_ORACLE_GRANULARITY; i += 1) {
        await adapter.update(addresses.tokens.WETH, addresses.tokens.DAI);
        ethers.provider.send('evm_increaseTime', [TWAP_ORACLE_WINDOW / TWAP_ORACLE_GRANULARITY]);
      }
      const { amountOut } = await adapter.getPrice(addresses.tokens.WETH, addresses.tokens.DAI);
      console.log('price', ethers.utils.formatEther(amountOut));
      expect(amountOut).to.be.gt(ethers.utils.parseEther('500'));
    });
  });

  describe('Uniswap TWAP V3x', function () {
    // it('should not get the price of FEI', async function () {
    //   await adapter.update(addresses.tokens.YFI, addresses.tokens.WETH);
    //   await expect(univ3.getPrice(addresses.tokens.YFI, addresses.tokens.WETH)).to.be.reverted;
    // });

    it('should get the price of DAI', async function () {
      const { amountOut } = await univ3.getPrice(addresses.tokens.WETH, addresses.tokens.DAI);
      expect(ethers.utils.formatEther(amountOut)).to.be.eq('3938.801407293532197958');
    });
    it('should get the price of DAI inverse', async function () {
      const { amountOut } = await univ3.getPrice(addresses.tokens.DAI, addresses.tokens.WETH);
      expect(ethers.utils.formatEther(amountOut)).to.be.eq('0.000253884341096326');
    });
  });

  describe('Global Oracle', function () {
    it('should get the price of YFI with enough observations', async function () {
      for (let i = 0; i < TWAP_ORACLE_GRANULARITY; i += 1) {
        await adapter.update(addresses.tokens.YFI, addresses.tokens.WETH);
        ethers.provider.send('evm_increaseTime', [TWAP_ORACLE_WINDOW / TWAP_ORACLE_GRANULARITY]);
      }
      let price = await priceOracle.connect(owner).getPrice(addresses.tokens.YFI, addresses.tokens.WETH);
      price = ethers.BigNumber.from(1).div(price);
      expect(price).to.be.gt(ethers.utils.parseEther('15'));
    });
  });
});
