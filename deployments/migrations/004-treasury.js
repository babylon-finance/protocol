module.exports = async ({ getNamedAccounts, deployments, ethers, getRapid }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('Treasury', {
    from: deployer,
    args: [controller.address],
    log: true,
    gasPrice,
  });
};

module.exports.tags = ['Treasury'];
module.exports.dependencies = ['Distributor'];
