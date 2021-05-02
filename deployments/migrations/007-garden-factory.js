module.exports = async ({ getNamedAccounts, deployments, ethers, getRapid }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  await deploy('GardenFactory', {
    from: deployer,
    args: [],
    log: true,
    gasPrice,
  });
};

module.exports.tags = ['GardenFactory'];
module.exports.dependencies = ['Gate'];
