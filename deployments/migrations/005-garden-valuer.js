module.exports = async ({
  network,
  getTenderlyContract,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getGasPrice,
  getConroller,
}) => {
  const { deploy } = deployments;
  const { deployer, owner } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const { maxPriorityFeePerGas } = await getGasPrice();
  const contract = 'GardenValuer';

  const controller = await getController();

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address],
    log: true,
    maxPriorityFeePerGas,
  });

  if (deployment.newlyDeployed) {
    console.log(`Setting garden valuer on controller ${deployment.address}`);
    await (await controller.editGardenValuer(deployment.address, { maxPriorityFeePerGas })).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['Valuer'];
