const addresses = require('./addresses');
/**
 * Gets the whale address of a given asset
 * @param {string} address - Address of the ERC20 asset
 */
function getAssetWhale(address) {
  let whaleAddress;
  switch (address.toLowerCase()) {
    case addresses.tokens.DAI.toLowerCase():
      whaleAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
      break;
    case addresses.tokens.USDC.toLowerCase():
      whaleAddress = '0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503';
      break;
    case addresses.tokens.WETH.toLowerCase():
      whaleAddress = '0x2f0b23f53734252bda2277357e97e1517d6b042a';
      break;
  }
  return whaleAddress;
}
module.exports = {
  getAssetWhale,
};
