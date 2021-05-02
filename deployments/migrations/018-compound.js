const addresses = require('../../lib/addresses');

module.exports = async ({ getNamedAccounts, deployments, ethers, getRapid }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('CompoundLendIntegration', {
    from: deployer,
    args: [controller.address, addresses.tokens.WETH],
    log: true,
    gasPrice,
  });
};

module.exports.tags = ['Compound'];
module.exports.dependencies = ['Yearn'];
