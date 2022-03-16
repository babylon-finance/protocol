const { impersonateAddress } = require('./rpc');
const { getERC20, parse, from, eth } = require('../test/utils/test-helpers');
const addresses = require('./addresses');

const ETH = addresses.tokens.ETH;

/**
 * Gets the whale address of a given asset
 * @param {string} address - Address of the ERC20 asset
 */
function getAssetWhale(address) {
  let whaleAddress;
  switch (address.toLowerCase()) {
    case addresses.tokens.DAI.toLowerCase():
      whaleAddress = '0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7';
      break;
    case addresses.tokens.USDC.toLowerCase():
      whaleAddress = '0x0a59649758aa4d66e25f08dd01271e891fe52199';
      break;
    case addresses.tokens.WETH.toLowerCase():
      whaleAddress = '0xC8dDA504356195ba5344E5a9826Ce07DfEaA97b6';
      break;
    case addresses.tokens.BABL.toLowerCase():
      whaleAddress = '0x40154ad8014df019a53440a60ed351dfba47574e';
      break;
    case addresses.tokens.FEI.toLowerCase():
      whaleAddress = '0x06cb22615ba53e60d67bf6c341a0fd5e718e1655';
      break;
    case addresses.tokens.FRAX.toLowerCase():
      whaleAddress = '0x94671a3cee8c7a12ea72602978d1bb84e920efb2';
      break;
    case addresses.tokens.AAVE.toLowerCase():
      whaleAddress = '0x4da27a545c0c5b758a6ba100e3a049001de870f5';
      break;
  }
  return whaleAddress;
}

const TOKEN_WHALE_MAP = {
  [addresses.tokens.ETH]: '0x00000000219ab540356cBB839Cbe05303d7705Fa',
  [addresses.tokens.WETH]: '0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E',
  [addresses.tokens.DAI]: '0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7',
  [addresses.tokens.USDC]: '0x0a59649758aa4d66e25f08dd01271e891fe52199',
  [addresses.tokens.WBTC]: '0x9ff58f4ffb29fa2266ab25e75e2a8b3503311656',
  [addresses.tokens.BABL]: '0x40154ad8014df019a53440a60ed351dfba47574e',
  [addresses.tokens.FEI]: '0x06cb22615ba53e60d67bf6c341a0fd5e718e1655',
  [addresses.tokens.FRAX]: '0x94671a3cee8c7a12ea72602978d1bb84e920efb2',
  [addresses.tokens.AAVE]: '0x4da27a545c0c5b758a6ba100e3a049001de870f5',
};

const TOKEN_AMOUNT_MAP = {
  [addresses.tokens.ETH]: eth(100),
  [addresses.tokens.WETH]: eth(100),
  [addresses.tokens.BABL]: eth(20000),
  [addresses.tokens.AAVE]: eth(100),
  [addresses.tokens.DAI]: eth(1e6),
  [addresses.tokens.FEI]: eth(1e6),
  [addresses.tokens.FRAX]: eth(1e5),
  [addresses.tokens.USDC]: from(1e6 * 1e6),
  [addresses.tokens.WBTC]: from(10e8),
};

async function fund(accounts, { tokens, amounts } = {}) {
  const { ethers } = require('hardhat');

  tokens = tokens || [
    addresses.tokens.ETH,
    addresses.tokens.WETH,
    addresses.tokens.DAI,
    addresses.tokens.USDC,
    addresses.tokens.WBTC,
    addresses.tokens.BABL,
    addresses.tokens.FEI,
    addresses.tokens.FRAX,
    addresses.tokens.AAVE,
  ];
  amounts = amounts || {};
  const tokenContracts = {};
  const whaleSigners = {};

  for (const account of accounts) {
    for (let i = 0; i < tokens.length; i++) {
      const token = tokens[i];
      if (!whaleSigners[token]) {
        whaleSigners[token] = await impersonateAddress(TOKEN_WHALE_MAP[token]);
      }
      if (token !== ETH) {
        if (!tokenContracts[token]) {
          tokenContracts[token] = await getERC20(token);
        }
        await tokenContracts[token]
          .connect(whaleSigners[token])
          .transfer(account, amounts[i] ? amounts[i] : TOKEN_AMOUNT_MAP[token], {
            gasPrice: 0,
          });
      } else {
        await whaleSigners[token].sendTransaction({
          to: account,
          value: amounts[i] ? amounts[i] : TOKEN_AMOUNT_MAP[token],
        });
      }
    }
  }
}

async function createWallets(number, fundOpts = {}) {
  const wallets = [];
  for (let i = 0; i < number; i++) {
    wallets.push(ethers.Wallet.createRandom().connect(ethers.provider));
  }
  if (fund) {
    await fund(
      wallets.map((o) => o.address),
      fundOpts,
    );
  }
  return wallets;
}

module.exports = {
  getAssetWhale,
  fund,
  createWallets,
};
