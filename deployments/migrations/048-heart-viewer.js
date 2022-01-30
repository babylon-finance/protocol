module.exports = async ({
  network,
  getTenderlyContract,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getGasPrice,
  getContract,
  getController,
}) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getGasPrice();
  const contract = 'HeartViewer';

  const controller = await deployments.get('BabControllerProxy');
  const governor = await getContract('BabylonGovernor');

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, governor.address],
    log: true,
    gasPrice,
  });

  if (deployment.newlyDeployed) {
    console.log(`Deployed Heart Viewer ${deployment.address}`);
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['Viewer'];
