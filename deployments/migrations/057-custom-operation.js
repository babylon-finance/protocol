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
  const contract = 'CustomOperation';

  const controller = await getController();

  const deployment = await deploy(contract, {
    from: deployer,
    args: ['custom', controller.address],
    log: true,
    ...(await getGasPrice()),
  });

  if (deployment.newlyDeployed) {
    console.log(`Adding custom operation ${contract}(${deployment.address}) to BabController`);
    await (await controller.setOperation(5, deployment.address, { ...(await getGasPrice()) })).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['CustomOp'];
