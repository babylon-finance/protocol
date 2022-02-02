module.exports = async ({
  network,
  getTenderlyContract,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getGasPrice,
  getController,
}) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const { maxPriorityFeePerGas } = await getGasPrice();
  const contract = 'Treasury';

  const controller = await getController();

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address],
    log: true,
    maxPriorityFeePerGas,
  });

  if (deployment.newlyDeployed) {
    console.log(`Setting treasury on controller ${deployment.address}`);
    await (await controller.editTreasury(deployment.address, { maxPriorityFeePerGas })).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['Treasury'];
