const { ADDRESS_ZERO } = require('../../lib/constants');

module.exports = async ({ getTenderlyContract, getNamedAccounts, deployments, getRapid, network, tenderly }) => {
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();
  const { deploy } = deployments;

  const controller = await deployments.get('BabControllerProxy');

  const token = await deploy('BABLToken', {
    from: deployer,
    args: [ADDRESS_ZERO, controller.address],
    log: true,
    gasPrice,
  });

  if (network.live && token.newlyDeployed) {
    const contract = await getTenderlyContract('BABLToken');
    await tenderly.push(contract);
  }
};

module.exports.tags = ['Token'];
module.exports.dependencies = ['Controller'];
