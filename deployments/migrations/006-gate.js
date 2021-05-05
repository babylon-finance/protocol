module.exports = async ({ getNamedAccounts, deployments, ethers, getRapid }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('IshtarGate', {
    from: deployer,
    args: [controller.address, 'http://json.api/test'],
    log: true,
    gasPrice,
  });
};

module.exports.tags = ['Gate'];
module.exports.dependencies = ['Valuer'];
