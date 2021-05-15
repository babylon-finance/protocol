const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require('../../lib/system.js');
const addresses = require('../../lib/addresses');

module.exports = async ({ getNamedAccounts, deployments, ethers, getRapid, getContract }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('UniswapTWAP', {
    from: deployer,
    args: [controller.address, addresses.uniswap.factory, TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY],
    log: true,
    gasPrice,
  });

  await deploy('UniswapTWAPV3', {
    from: deployer,
    args: [controller.address, addresses.uniswap.v3.factory],
    log: true,
    gasPrice,
  });
};

module.exports.tags = ['TWAP'];
