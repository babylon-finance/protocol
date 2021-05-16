module.exports = async ({
  network,
  getTenderlyContracts,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getRapid,
}) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const safeDecimalMath = await deploy('SafeDecimalMath', {
    from: deployer,
    args: [],
    log: true,
    gasPrice,
  });

  const bablToken = await deployments.get('BABLToken');
  const controller = await deployments.get('BabControllerProxy');

  const rewardsDistributor = await deploy('RewardsDistributor', {
    from: deployer,
    args: [bablToken.address, controller.address],
    log: true,
    gasPrice,
    libraries: {
      SafeDecimalMath: safeDecimalMath.address,
    },
  });

  if (rewardsDistributor.newlyDeployed) {
    const bablTokenContract = await ethers.getContractAt('BABLToken', bablToken.address);

    // Sets the Rewards Distributor address into the BABL Token contract
    await bablTokenContract.setRewardsDistributor(rewardsDistributor.address, { gasPrice });
  }

  if (network.live && rewardsDistributor.newlyDeployed) {
    // fails, mostly likely because of the usage of libs
    // await tenderly.push(await getTenderlyContracts(['SafeDecimalMath', 'RewardsDistributor']));
  }
};

module.exports.tags = ['Distributor'];
module.exports.dependencies = ['Controller, Token'];
