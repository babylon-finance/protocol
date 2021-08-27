const setCode = async (target, mock) => {
  const hre = require('hardhat');
  await hre.network.provider.send('hardhat_setCode', [target, mock]);
};

const impersonateAddress = async (address) => {
  const hre = require('hardhat');
  await hre.network.provider.request({
    method: 'hardhat_impersonateAccount',
    params: [address],
  });

  const signer = await ethers.provider.getSigner(address);
  signer.address = signer._address;

  return signer;
};

const takeSnapshot = async () => {
  const hre = require('hardhat');
  return hre.network.provider.request({
    method: 'evm_snapshot',
    params: [],
  });
};

const restoreSnapshot = async (id) => {
  const hre = require('hardhat');
  await hre.network.provider.request({
    method: 'evm_revert',
    params: [id],
  });
};

module.exports = {
  impersonateAddress,
  takeSnapshot,
  restoreSnapshot,
  setCode,
};
