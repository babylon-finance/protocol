module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('GardenValuer', {
    from: deployer,
    args: [controller.address],
    log: true,
  });
};

module.exports.tags = ['Valuer'];
module.exports.dependencies = ['Treasury'];
