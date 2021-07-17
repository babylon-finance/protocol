const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ADDRESS_ZERO, MINUS_ONE_ETH, ONE_ETH } = require('../lib/constants');
const addresses = require('../lib/addresses');
const { setupTests } = require('./fixtures/GardenFixture');

describe('Treasury', function () {
  let signer1;
  let treasury;
  let weth;
  let owner;
  let wethWhaleSigner;
  let TOKEN_MAP;

  beforeEach(async () => {
    ({ owner, wethWhaleSigner, signer1, treasury, TOKEN_MAP, weth } = await setupTests()());

    await weth.connect(wethWhaleSigner).transfer(treasury.address, ONE_ETH);
  });

  describe('sendTreasuryFunds', async function () {
    [
      { token: addresses.tokens.WETH, name: 'WETH', fee: eth() },
      { token: addresses.tokens.DAI, name: 'DAI', fee: eth(2000) },
      { token: addresses.tokens.USDC, name: 'USDC', fee: from(2000 * 1e6) },
      { token: addresses.tokens.WBTC, name: 'WBTC', fee: from(0.05 * 1e8) },
    ].forEach(({ token, name, fee }) => {
      it.only(`can send ${token}`, async function () {
        await expect(() =>
          treasury.connect(owner).sendTreasuryFunds(token, ONE_ETH, signer1.address, { gasPrice: 0 }),
        ).to.changeTokenBalances(weth, [treasury, signer1], [MINUS_ONE_ETH, ONE_ETH]);
      });
    });

    it('fails to send zero address asset', async function () {
      await expect(
        treasury.connect(owner).sendTreasuryFunds(ADDRESS_ZERO, ONE_ETH, signer1.address, { gasPrice: 0 }),
      ).to.be.revertedWith('Asset must exist');
    });

    it('fails to send funds to zero address', async function () {
      await expect(
        treasury.connect(owner).sendTreasuryFunds(addresses.tokens.WETH, ONE_ETH, ADDRESS_ZERO, { gasPrice: 0 }),
      ).to.be.revertedWith('Target address must exist');
    });

    it('fails if not enough funds in treasury', async function () {
      await expect(
        treasury
          .connect(owner)
          .sendTreasuryFunds(addresses.tokens.WETH, ONE_ETH.mul(100), signer1.address, { gasPrice: 0 }),
      ).to.be.reverted;
    });
  });
});
