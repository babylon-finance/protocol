const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { loadFixture } = waffle;
const { ADDRESS_ZERO, MINUS_ONE_ETH, ONE_ETH } = require('../lib/constants');
const addresses = require('../lib/addresses');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');

describe('Treasury', function () {
  let signer1;
  let treasury;
  let weth;
  let owner;
  let wethWhaleSigner;

  beforeEach(async () => {
    ({ owner, wethWhaleSigner, signer1, treasury } = await loadFixture(deployFolioFixture));

    weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
    await weth.connect(wethWhaleSigner).transfer(treasury.address, ONE_ETH);
  });

  describe('sendTreasuryFunds', async function () {
    it('can send funds', async function () {
      await expect(() =>
        treasury.connect(owner).sendTreasuryFunds(addresses.tokens.WETH, ONE_ETH, signer1.address, { gasPrice: 0 }),
      ).to.changeTokenBalances(weth, [treasury, signer1], [MINUS_ONE_ETH, ONE_ETH]);
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
      ).to.be.revertedWith('Not enough funds in treasury');
    });
  });
});
