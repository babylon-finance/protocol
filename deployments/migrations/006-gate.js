module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('IshtarGate', {
    from: deployer,
    args: [controller.address, 'http://json.api/test'],
    log: true,
  });
};

module.exports.tags = ['Gate'];
module.exports.dependencies = ['Valuer'];
