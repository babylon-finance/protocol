module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('YieldFarmingStrategyFactory', {
    from: deployer,
    args: [],
    log: true,
  });
};

module.exports.tags = ['YieldFarmingStrategy'];
module.exports.dependencies = ['LiquidityPoolStrategy'];
