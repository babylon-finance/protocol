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
  const { deployer, owner } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const { maxPriorityFeePerGas } = await getGasPrice();
  const contract = 'BuyOperation';

  const controller = await getController();

  const deployment = await deploy(contract, {
    from: deployer,
    args: ['buy', controller.address],
    log: true,
    maxPriorityFeePerGas,
  });

  if (deployment.newlyDeployed) {
    console.log(`Adding operation ${contract}(${deployment.address}) to BabController`);
    await (await controller.setOperation(0, deployment.address, { maxPriorityFeePerGas })).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['BuyOp'];
