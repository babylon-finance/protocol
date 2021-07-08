const { from, eth, parse } = require('./helpers');
const { impersonateAddress } = require('./rpc');
const addresses = require('./addresses');

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
  }
  return whaleAddress;
}

const TOKEN_WHALE_MAP = {
  [addresses.tokens.WETH]: '0xC8dDA504356195ba5344E5a9826Ce07DfEaA97b6',
  [addresses.tokens.DAI]: '0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7',
  [addresses.tokens.USDC]: '0x0a59649758aa4d66e25f08dd01271e891fe52199',
  [addresses.tokens.WBTC]: '0x9ff58f4ffb29fa2266ab25e75e2a8b3503311656',
};

const TOKEN_AMOUNT_MAP = {
  [addresses.tokens.WETH]: eth(100),
  [addresses.tokens.DAI]: eth(1e6),
  [addresses.tokens.USDC]: from(1e6 * 1e6),
  [addresses.tokens.WBTC]: from(10e8),
};

async function fund(addresses, tokens) {
  const { ethers } = require('hardhat');
  const tokenContracts = {};
  const whaleSigners = {};

  for (const address of addresses) {
    for (const token of tokens) {
      if (!tokenContracts[token]) {
        tokenContracts[token] = await ethers.getContractAt('IERC20', token);
      }
      if (!whaleSigners[token]) {
        whaleSigners[token] = await impersonateAddress(TOKEN_WHALE_MAP[token]);
      }
      await tokenContracts[token].connect(whaleSigners[token]).transfer(address, TOKEN_AMOUNT_MAP[token], {
        gasPrice: 0,
      });
    }
  }
}

module.exports = {
  getAssetWhale,
  fund,
};
