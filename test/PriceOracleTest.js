const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { loadFixture } = waffle;

const addresses = require('../utils/addresses');
const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require('../utils/system.js');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');

describe('PriceOracle', function () {
  let controller;
  let oracle;
  let garden;
  let adapter;

  beforeEach(async () => {
    const { babController, priceOracle, comunities } = await loadFixture(deployFolioFixture);
    garden = comunities.one;
    controller = babController;
    oracle = priceOracle;
    adapter = await ethers.getContractAt('UniswapTWAP', (await oracle.getAdapters())[0]);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployedc = await controller.deployed();
      const deployed = await oracle.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedc).to.equal(true);
    });
  });

  describe('UniswapAnchoredView', function () {
    it('should get the price of ETH/DAI', async function () {
      const price = await oracle.getPrice(addresses.tokens.WETH, addresses.tokens.DAI);
      expect(price).to.be.gt(ethers.utils.parseEther('500'));
    });

    it('should get the price of DAI/USDC', async function () {
      const price = await oracle.getPrice(addresses.tokens.DAI, addresses.tokens.USDC);
      expect(price).to.be.lt(ethers.utils.parseEther('1.1'));
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
      expect(amountOut).to.be.gt(ethers.utils.parseEther('500'));
    });
  });

  describe('Global Oracle', function () {
    it('should get the price of YFI with enough observations', async function () {
      for (let i = 0; i < TWAP_ORACLE_GRANULARITY; i += 1) {
        await adapter.update(addresses.tokens.YFI, addresses.tokens.WETH);
        ethers.provider.send('evm_increaseTime', [TWAP_ORACLE_WINDOW / TWAP_ORACLE_GRANULARITY]);
      }
      const price = await oracle.getPrice(addresses.tokens.YFI, addresses.tokens.WETH);
      expect(price).to.be.gt(ethers.utils.parseEther('15'));
    });
  });
});
