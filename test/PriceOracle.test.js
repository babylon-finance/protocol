const { expect } = require('chai');
const { ethers } = require('hardhat');

const addresses = require('../lib/addresses');
const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require('../lib/system.js');
const { setupTests } = require('./fixtures/GardenFixture');

describe('PriceOracle', function () {
  let priceOracle;
  let univ2;
  let univ3;
  let owner;

  beforeEach(async () => {
    ({ priceOracle, owner, univ2 } = await setupTests()());
    univ3 = await ethers.getContractAt('UniswapTWAP', (await priceOracle.getAdapters())[0]);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await priceOracle.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe('UniswapAnchoredView', function () {
    it('should get the price of ETH/DAI', async function () {
      const price = await priceOracle.connect(owner).getPrice(addresses.tokens.WETH, addresses.tokens.DAI);
      expect(price).to.be.gt(ethers.utils.parseEther('2000'));
    });

    it('should get the price of DAI/USDC', async function () {
      const price = await priceOracle.connect(owner).getPrice(addresses.tokens.DAI, addresses.tokens.USDC);
      expect(price).to.be.lt(ethers.utils.parseEther('1.1'));
    });
    it('should get the price of WETH/USDC', async function () {
      const price = await priceOracle.connect(owner).getPrice(addresses.tokens.WETH, addresses.tokens.USDC);
      expect(price).to.be.gt(ethers.utils.parseEther('2000'));
    });
  });

  describe('Uniswap TWAP V2', function () {
    it('should not get the price of YFI without enough observations', async function () {
      await univ2.update(addresses.tokens.YFI, addresses.tokens.WETH);
      await expect(univ2.getPrice(addresses.tokens.YFI, addresses.tokens.WETH)).to.be.reverted;
    });

    it('should get the price of YFI with enough observations', async function () {
      for (let i = 0; i < TWAP_ORACLE_GRANULARITY; i += 1) {
        await univ2.update(addresses.tokens.YFI, addresses.tokens.WETH);
        ethers.provider.send('evm_increaseTime', [TWAP_ORACLE_WINDOW / TWAP_ORACLE_GRANULARITY]);
      }
      const { amountOut } = await univ2.getPrice(addresses.tokens.YFI, addresses.tokens.WETH);
      expect(amountOut).to.be.gt(ethers.utils.parseEther('15'));
    });

    it('should get the price of DAI', async function () {
      for (let i = 0; i < TWAP_ORACLE_GRANULARITY; i += 1) {
        await univ2.update(addresses.tokens.WETH, addresses.tokens.DAI);
        ethers.provider.send('evm_increaseTime', [TWAP_ORACLE_WINDOW / TWAP_ORACLE_GRANULARITY]);
      }
      const { amountOut } = await univ2.getPrice(addresses.tokens.WETH, addresses.tokens.DAI);
      expect(amountOut).to.be.gt(ethers.utils.parseEther('500'));
    });
  });

  describe('Uniswap TWAP V3', function () {
    it('should get the price of YFI', async function () {
      const { amountOut } = await univ3.getPrice(addresses.tokens.WETH, addresses.tokens.YFI);
      expect(ethers.utils.formatEther(amountOut)).to.be.eq('0.05571996387116252');
    });

    it('should get the price of WBTC', async function () {
      const { amountOut } = await univ3.getPrice(addresses.tokens.WETH, addresses.tokens.WBTC);
      expect(ethers.utils.formatEther(amountOut)).to.be.eq('0.071417837761293314');
    });

    it('should get the price of DAI', async function () {
      const { amountOut } = await univ3.getPrice(addresses.tokens.WETH, addresses.tokens.DAI);
      expect(ethers.utils.formatEther(amountOut)).to.be.eq('3938.801407293532197958');
    });

    it('should get the price of USDC', async function () {
      const { amountOut } = await univ3.getPrice(addresses.tokens.WETH, addresses.tokens.USDC);
      expect(ethers.utils.formatEther(amountOut)).to.be.eq('3958.944346368296183367');
    });

    it('should get the price of DAI inverse', async function () {
      const { amountOut } = await univ3.getPrice(addresses.tokens.DAI, addresses.tokens.WETH);
      expect(ethers.utils.formatEther(amountOut)).to.be.eq('0.000253884341096326');
    });
  });

  describe('Price Oracle', function () {
    it('should get the price of YFI', async function () {
      const price = await priceOracle.connect(owner).getPrice(addresses.tokens.YFI, addresses.tokens.WETH);
      expect(price).to.be.eq('17946888880119016864');
    });
  });
});
