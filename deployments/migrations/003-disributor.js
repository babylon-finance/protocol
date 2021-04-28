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

  const rewardsDistributor = await deploy('RewardsDistributor', {
    from: deployer,
    args: [bablToken.address, controller.address],
    log: true,
    libraries: {
      SafeDecimalMath: safeDecimalMath.address,
    },
  });

  const bablTokenContract = await ethers.getContractAt('BABLToken', bablToken.address);

  // Sets the Rewards Distributor address into the BABL Token contract
  await bablTokenContract.setRewardsDistributor(rewardsDistributor.address);
};

module.exports.tags = ['Distributor'];
module.exports.dependencies = ['Registry'];
