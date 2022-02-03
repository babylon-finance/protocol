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
  const { maxPriorityFeePerGas } = await getGasPrice();
  console.log('check 0');
  const contract = 'RewardsAssistant';

  const rewardsDistributor = await getContract('RewardsDistributor', 'RewardsDistributorProxy');
  const controller = await getController();
  console.log('check 1');
  const rewardsAssistant = await deploy(contract, {
    from: deployer,
    args: [controller.address],
    log: true,
    maxPriorityFeePerGas,
  });
  console.log('check 2');

  if (rewardsAssistant.newlyDeployed) {
    console.log(`Setting rewards assistant on rewards distributor ${rewardsAssistant.address}`);
    await (await rewardsDistributor.setRewardsAssistant(rewardsAssistant.address, { maxPriorityFeePerGas })).wait();
  }
  console.log('check 3');

  if (network.live && rewardsDistributor.newlyDeployed) {
    // fails, mostly likely because of the usage of libs
    await tenderly.push(await getTenderlyContracts(['RewardsAssistant']));
  }
};

module.exports.tags = ['RewardsAssistant'];
