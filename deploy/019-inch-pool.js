const addresses = require('../utils/addresses');

module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('OneInchPoolIntegration', {
    from: deployer,
    args: [controller.address, addresses.tokens.WETH, addresses.oneinch.factory],
    log: true,
  });
};

module.exports.tags = ['OneInchPool'];
