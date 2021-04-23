const addresses = require('../lib/addresses');

module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('SushiswapPoolIntegration', {
    from: deployer,
    args: [controller.address, addresses.tokens.WETH, addresses.sushiswap.router],
    log: true,
  });
};

module.exports.tags = ['Sushiswap'];
