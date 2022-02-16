const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ADDRESS_ZERO } = require('lib/constants');
const addresses = require('lib/addresses');
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
  let treasury;
  let owner;
  let signer1;
  let erc20;

  beforeEach(async () => {
    [, , owner, signer1] = await ethers.getSigners();
    const treasuryFactory = await ethers.getContractFactory('Treasury');
    treasury = await treasuryFactory.deploy();
    await treasury.transferOwnership(owner.address);

    const erc20Fatory = await ethers.getContractFactory('ERC20Mock');
    erc20 = await erc20Fatory.deploy('Babylon Finance', 'BABL', treasury.address, 1e6);
  });

  describe('sendTreasuryFunds', async function () {
    it('can send', async function () {
      const amount = eth();
      await expect(() =>
        treasury.connect(owner).sendTreasuryFunds(erc20.address, amount, signer1.address),
      ).to.changeTokenBalances(erc20, [treasury, signer1], [amount.mul(-1), amount]);
    });

    it(`can send ETH`, async function () {
      await expect(() =>
        treasury.connect(owner).sendTreasuryETH(eth(), signer1.address, { gasPrice: 0 }),
      ).to.changeEtherBalances([treasury, signer1], [eth(-1), eth()]);
    });

    it('fails to send zero address asset', async function () {
      await expect(
        treasury.connect(owner).sendTreasuryFunds(ADDRESS_ZERO, eth(), signer1.address, { gasPrice: 0 }),
      ).to.be.revertedWith('Asset must exist');
    });

    it('fails to send funds to zero address', async function () {
      await expect(
        treasury.connect(owner).sendTreasuryFunds(addresses.tokens.WETH, eth(), ADDRESS_ZERO, { gasPrice: 0 }),
      ).to.be.revertedWith('Target address must exist');
    });
  });
});
