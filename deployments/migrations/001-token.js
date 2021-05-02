const { ADDRESS_ZERO } = require('../../lib/constants');

module.exports = async ({ getNamedAccounts, deployments, getRapid }) => {
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();
  const { deploy } = deployments;

  const controller = await deployments.get('BabControllerProxy');

  await deploy('BABLToken', {
    from: deployer,
    args: [ADDRESS_ZERO, controller.address],
    log: true,
    gasPrice,
  });
};

module.exports.tags = ['Token'];
module.exports.dependencies = ['Controller'];
