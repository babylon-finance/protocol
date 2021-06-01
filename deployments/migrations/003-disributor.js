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
  const { deployer, owner } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const bablToken = await deployments.get('BABLToken');
  const controller = await deployments.get('BabControllerProxy');

  const rewardsDistributor = await upgradesDeployer.deployOrUpgrade(
    'RewardsDistributor',
    { from: deployer, log: true, gasPrice },
    {
      initializer: { method: 'initialize', args: [bablToken.address, controller.address] },
    },
  );

  if (rewardsDistributor.newlyDeployed) {
    const bablTokenContract = await ethers.getContractAt('BABLToken', bablToken.address);

    // Sets the Rewards Distributor address into the BABL Token contract
    await bablTokenContract.setRewardsDistributor(rewardsDistributor.address, { gasPrice });
  }

  if (network.live && rewardsDistributor.newlyDeployed) {
    // fails, mostly likely because of the usage of libs
    await tenderly.push(await getTenderlyContracts(['RewardsDistributor', 'RewardsDistributorProxy']));
  }
};

module.exports.tags = ['Distributor'];
