const { ADDRESS_ZERO } = require('../lib/constants');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('BABLToken', {
    from: deployer,
    args: [ADDRESS_ZERO, controller.address],
    log: true,
  });
};

module.exports.tags = ['Token'];
