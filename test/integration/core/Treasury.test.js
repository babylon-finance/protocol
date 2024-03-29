const { expect } = require('chai');
const { ethers } = require('hardhat');
const { fund } = require('lib/whale');
const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');
const { pick, skipIfFast, getERC20, from, eth } = require('utils/test-helpers');

skipIfFast('Treasury', function () {
  let signer1;
  let treasury;
  let owner;

  beforeEach(async () => {
    ({ owner, signer1, treasury } = await setupTests()());

    await fund([treasury.address]);
  });

  describe('sendTreasuryFunds', async function () {
    pick([
      { token: addresses.tokens.WETH, name: 'WETH', amount: eth() },
      { token: addresses.tokens.DAI, name: 'DAI', amount: eth(2000) },
      { token: addresses.tokens.USDC, name: 'USDC', amount: from(2000 * 1e6) },
      { token: addresses.tokens.WBTC, name: 'WBTC', amount: from(0.05 * 1e8) },
    ]).forEach(({ token, name, amount }) => {
      it(`can send ${name}`, async function () {
        const erc20 = await getERC20(token);
        await expect(() =>
          treasury.connect(owner).sendTreasuryFunds(token, amount, signer1.address, { gasPrice: 0 }),
        ).to.changeTokenBalances(erc20, [treasury, signer1], [amount.mul(-1), amount]);
      });
    });
  });
});
