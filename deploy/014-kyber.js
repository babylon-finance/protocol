const addresses = require('../utils/addresses');

module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('KyberTradeIntegration', {
    from: deployer,
    args: [controller.address, addresses.tokens.WETH, addresses.kyber.proxy],
    log: true,
  });
};

module.exports.tags = ['Kyber'];
