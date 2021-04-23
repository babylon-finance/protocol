module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('GardenFactory', {
    from: deployer,
    args: [],
    log: true,
  });
};

module.exports.tags = ['GardenFactory'];
module.exports.dependencies = ['Gate'];
