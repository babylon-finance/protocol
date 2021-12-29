const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ADDRESS_ZERO, MINUS_ONE_ETH, ONE_ETH, GARDENS } = require('lib/constants');
const { fund } = require('lib/whale');
const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');
const {
  pick,
  increaseTime,
  normalizeDecimals,
  getERC20,
  getContract,
  parse,
  from,
  eth,
} = require('utils/test-helpers');

describe('Treasury', function () {
  let signer1;
  let treasury;
  let weth;
  let owner;
  let wethWhaleSigner;

  beforeEach(async () => {
    ({ owner, wethWhaleSigner, signer1, treasury, weth } = await setupTests()());

    await fund([treasury.address]);
  });

  describe('sendTreasuryFunds', async function () {
    pick(GARDENS).forEach(({ token, name, amount }) => {
      it(`can send ${name}`, async function () {
        const erc20 = await getERC20(token);
        await expect(() =>
          treasury.connect(owner).sendTreasuryFunds(token, amount, signer1.address, { gasPrice: 0 }),
        ).to.changeTokenBalances(erc20, [treasury, signer1], [amount.mul(-1), amount]);
      });
    });

    it(`can send ETH`, async function () {
      await expect(() =>
        treasury.connect(owner).sendTreasuryETH(eth(), signer1.address, { gasPrice: 0 }),
      ).to.changeEtherBalances([treasury, signer1], [eth(-1), eth()]);
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
          .sendTreasuryFunds(addresses.tokens.WETH, eth(99999999), signer1.address, { gasPrice: 0 }),
      ).to.be.reverted;
    });
  });
});
