module.exports = async ({
  network,
  getTenderlyContracts,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getGasPrice,
  getController,
  getSigner,
}) => {
  const { deploy } = deployments;
  const { deployer, owner } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const gasPrice = await getGasPrice();

  const rewardsDistributor = await getContract('RewardsDistributor', 'RewardsDistributorProxy');
  const controller = await getController();

  const rewardsAssistant = await upgradesDeployer.deployAdminProxy(
    'RewardsAssistant',
    'RewardsAssistantProxy',
    { from: deployer, log: true, gasPrice },
    {
      initializer: { method: 'initialize', args: [controller.address] },
    },
  );

  if (rewardsAssistant.newlyDeployed) {
    console.log(`Setting rewards assistant on rewards distributor ${rewardsAssistant.address}`);
    await (await rewardsDistributor.setRewardsAssistant(rewardsAssistant.address, { gasPrice })).wait();
  }

  if (network.live && rewardsDistributor.newlyDeployed) {
    // fails, mostly likely because of the usage of libs
    await tenderly.push(await getTenderlyContracts(['RewardsAssistant', 'RewardsAssistantProxy']));
  }
};

module.exports.tags = ['DistributorAssistant'];
