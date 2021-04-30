const addresses = require('../lib/addresses');

module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('YearnVaultIntegration', {
    from: deployer,
    args: [controller.address, addresses.tokens.WETH, addresses.yearn.vaultRegistry],
    log: true,
  });
};

module.exports.tags = ['Yearn'];
module.exports.dependencies = ['OneInchPool'];
