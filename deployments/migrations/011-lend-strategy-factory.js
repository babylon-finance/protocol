module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('LendStrategyFactory', {
    from: deployer,
    args: [],
    log: true,
  });
};

module.exports.tags = ['LendStrategy'];
module.exports.dependencies = ['YieldFarmingStrategy'];
