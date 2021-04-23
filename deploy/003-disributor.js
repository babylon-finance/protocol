module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const safeDecimalMath = await deploy('SafeDecimalMath', {
    from: deployer,
    args: [],
    log: true,
  });

  const bablToken = await deployments.get('BABLToken');
  const controller = await deployments.get('BabControllerProxy');

  await deploy('RewardsDistributor', {
    from: deployer,
    args: [bablToken.address, controller.address],
    log: true,
    libraries: {
      SafeDecimalMath: safeDecimalMath.address,
    },
  });
};

module.exports.tags = ['Distributor'];
module.exports.dependencies = ['Registry'];
