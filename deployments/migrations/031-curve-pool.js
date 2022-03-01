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
  const contract = 'CurvePoolIntegration';

  const controller = await getController();

  const curveMetaRegistry = await deployments.get('CurveMetaRegistry');

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, curveMetaRegistry.address],
    log: true,
    ...(await getGasPrice()),
  });

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['CurvePool'];
