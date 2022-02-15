const { extendEnvironment } = require('hardhat/config');
const { getGasPrice } = require('../../lib/gasnow');
const { from } = require('../helpers');

extendEnvironment((hre) => {
  hre.getGasPrice = async () => {
    const chainId = await hre.getChainId();
    if (chainId === '1') {
      return await getGasPrice();
    } else return { maxPriorityFeePerGas: 1000000000 };
  };
});
