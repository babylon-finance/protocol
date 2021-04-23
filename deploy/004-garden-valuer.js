module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('Treasury', {
    from: deployer,
    args: [controller.address],
    log: true,
  });
};

module.exports.tags = ['Treasury'];
