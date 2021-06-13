const { ethers } = require('hardhat');

/**
 * Advance blockchain time by value. Has a random chance to deviate by 1 second.
 * Consider this during tests. Use `closeTo`.
 * @param {number} value - Amount of time to advance time by.
 */
async function increaseTime(value) {
  if (!ethers.BigNumber.isBigNumber(value)) {
    value = ethers.BigNumber.from(value);
  }
  await ethers.provider.send('evm_increaseTime', [value.toNumber()]);
  await ethers.provider.send('evm_mine');
}

/**
 * Can't await on transactionSend because it will never resolve due to
 * automine disabled. Save a promise instead and resolve it later.
 * Should set gasLimit on txs because default gasLimit is blockGasLimit.
 *   promise = signer.sendTransaction({
 *      to: signer.address,
 *      value: 1,
 *    });
 *   const txReceipt = await promise;
 * @param {func} Lambda to run within the same block.
 */
async function mineInBlock(lambda) {
  await ethers.provider.send('evm_setAutomine', [false]);
  await lambda();
  await ethers.provider.send('evm_mine');
  await ethers.provider.send('evm_setAutomine', [true]);
}

async function getTimestamp() {
  return (await ethers.provider.getBlock('latest')).timestamp;
}

async function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function getContract(contractName, deploymentName) {
  return await ethers.getContractAt(contractName, (await deployments.get(deploymentName || contractName)).address);
}

module.exports = {
  increaseTime,
  getTimestamp,
  mineInBlock,
  sleep,
  from: ethers.BigNumber.from,
  parse: ethers.utils.parseEther,
  getContract
};
