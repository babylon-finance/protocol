const addresses = require('../../lib/addresses');

module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('AaveLendIntegration', {
    from: deployer,
    args: [controller.address, addresses.tokens.WETH],
    log: true,
  });
};

module.exports.tags = ['Aave'];
module.exports.dependencies = ['Compound'];
