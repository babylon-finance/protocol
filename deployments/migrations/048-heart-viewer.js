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
  const governor = await deployments.get('BabylonGovernor');
  const heart = await deployments.get('HeartProxy');
  const HEART_GARDEN_ADDRES = '0xaA2D49A1d66A58B8DD0687E730FefC2823649791';

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, governor.address, heart.address],
    log: true,
    gasPrice,
  });

  if (deployment.newlyDeployed) {
    console.log(`Deployed Heart Viewer ${deployment.address}`);
  }

  if (network.live && deployment.newlyDeployed) {
    if (HEART_GARDEN_ADDRES) {
      await (await deployment.setHeartGarden(HEART_GARDEN_ADDRES, { gasPrice })).wait();
    }
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['HeartViewer'];
