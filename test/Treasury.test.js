const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { loadFixture } = waffle;
const { MINUS_ONE_ETH, ONE_ETH } = require('../utils/constants');
const addresses = require('../utils/addresses');
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

  describe.only('sendTreasuryFunds', async function () {
    it('can send funds', async function () {
      await expect(() =>
        treasury.connect(owner).sendTreasuryFunds(addresses.tokens.WETH, ONE_ETH, signer1.address, { gasPrice: 0 }),
      ).to.changeTokenBalances(weth, [treasury, signer1], [MINUS_ONE_ETH, ONE_ETH]);
    });
  });
});
