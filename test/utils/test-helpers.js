const { ethers } = require('hardhat');

function increaseTime(value) {
  ethers.provider.send('evm_increaseTime', [value]);
}

module.exports = {
  increaseTime,
};
