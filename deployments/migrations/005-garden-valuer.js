module.exports = async ({ getNamedAccounts, deployments, ethers, getRapid }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('GardenValuer', {
    from: deployer,
    args: [controller.address],
    log: true,
    gasPrice,
  });
};

module.exports.tags = ['Valuer'];
module.exports.dependencies = ['Treasury'];
