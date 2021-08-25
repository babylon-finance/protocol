const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ADDRESS_ZERO, MINUS_ONE_ETH, ONE_ETH } = require('lib/constants');
const { from, eth, parse } = require('lib/helpers');
const { fund } = require('lib/whale');
const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');

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
    [
      { token: addresses.tokens.WETH, name: 'WETH', amount: eth() },
      { token: addresses.tokens.DAI, name: 'DAI', amount: eth(2000) },
      { token: addresses.tokens.USDC, name: 'USDC', amount: from(2000 * 1e6) },
      { token: addresses.tokens.WBTC, name: 'WBTC', amount: from(0.05 * 1e8) },
    ].forEach(({ token, name, amount }) => {
      it(`can send ${name}`, async function () {
        const erc20 = await ethers.getContractAt('@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20', token);
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
