const addresses = require('../lib/addresses');

module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('UniswapPoolIntegration', {
    from: deployer,
    args: [controller.address, addresses.tokens.WETH, addresses.uniswap.router],
    log: true,
  });
};

module.exports.tags = ['Uniswap'];
module.exports.dependencies = ['Balancer'];
