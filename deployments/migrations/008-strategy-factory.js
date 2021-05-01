module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('StrategyFactory', {
    from: deployer,
    args: [],
    log: true,
  });
};

module.exports.tags = ['StrategyFactory'];
module.exports.dependencies = ['GardenFactory'];
