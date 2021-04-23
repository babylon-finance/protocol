module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('LendStrategyFactory', {
    from: deployer,
    args: [],
    log: true,
  });
};

module.exports.tags = ['LendStrategy'];
