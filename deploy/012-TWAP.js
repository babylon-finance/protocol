const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require('../utils/system.js');
const addresses = require('../utils/addresses');

module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('UniswapTWAP', {
    from: deployer,
    args: [controller.address, addresses.uniswap.factory, TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY],
    log: true,
  });
};

module.exports.tags = ['TWAP'];
