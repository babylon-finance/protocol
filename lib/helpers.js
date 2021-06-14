const { ethers } = require('ethers');

function eth(value = 1) {
  return ethers.utils.parseEther(value.toString());
}

module.exports = {
  from: ethers.BigNumber.from,
  parse: ethers.utils.parseEther,
  eth,
};
