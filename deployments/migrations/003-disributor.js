module.exports = async ({
  network,
  getTenderlyContracts,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getRapid,
  getController,
}) => {
  const { deploy } = deployments;
  const { deployer, owner } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const gasPrice = await getRapid();

  const bablToken = await deployments.get('BABLToken');
  const controller = await getController();

  const rewardsDistributor = await upgradesDeployer.deployAdminProxy(
    'RewardsDistributor',
    'RewardsDistributorProxy',
    { from: deployer, log: true, gasPrice },
    {
      initializer: { method: 'initialize', args: [bablToken.address, controller.address] },
    },
  );

  if (rewardsDistributor.newlyDeployed) {
    const bablTokenContract = await ethers.getContractAt('BABLToken', bablToken.address);

    console.log('Setting RewardsDistributor on BABLToken');
    await (await bablTokenContract.setRewardsDistributor(rewardsDistributor.address, { gasPrice })).wait();

    console.log(`Setting rewards distributor on controller ${rewardsDistributor.address}`);
    await (await controller.editRewardsDistributor(rewardsDistributor.address, { gasPrice })).wait();
  }

  if (network.live && rewardsDistributor.newlyDeployed) {
    // fails, mostly likely because of the usage of libs
    await tenderly.push(await getTenderlyContracts(['RewardsDistributor', 'RewardsDistributorProxy']));
  }
};

module.exports.tags = ['Distributor'];
