const { ethers } = require('hardhat');

async function increaseTime(value) {
  await ethers.provider.send('evm_increaseTime', [value]);
  return ethers.provider.send('evm_mine');
}

module.exports = {
  increaseTime,
  from: ethers.BigNumber.from,
};
