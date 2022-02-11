const { ADDRESS_ZERO } = require('../../lib/constants');

module.exports = async ({ getTenderlyContract, getNamedAccounts, deployments, getGasPrice, network, tenderly }) => {
  const { deployer } = await getNamedAccounts();
  const { deploy } = deployments;

  const controller = await deployments.get('BabControllerProxy');

  const token = await deploy('BABLToken', {
    from: deployer,
    args: [controller.address],
    log: true,
    ...(await getGasPrice()),
  });

  if (network.live && token.newlyDeployed) {
    const contract = await getTenderlyContract('BABLToken');
    await tenderly.push(contract);
  }
};

module.exports.tags = ['Token'];
