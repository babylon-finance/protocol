module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('LongStrategyFactory', {
    from: deployer,
    args: [],
    log: true,
  });
};

module.exports.tags = ['LongStrategy'];
module.exports.dependencies = ['GardenFactory'];
