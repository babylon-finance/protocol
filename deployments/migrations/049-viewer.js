module.exports = async ({
  network,
  getTenderlyContract,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getGasPrice,
  getController,
  getChainId,
}) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await getSigner(deployer);

  const controller = await deployments.get('BabControllerProxy');
  const governor = await deployments.get('BabylonGovernor');
  const heart = await deployments.get('HeartProxy');

  let HEART_GARDEN_ADDRES = '0xaA2D49A1d66A58B8DD0687E730FefC2823649791';
  const chainId = await getChainId();
  if (chainId === '1337') {
    HEART_GARDEN_ADDRES = '0xaA2D49A1d66A58B8DD0687E730FefC2823649791';
  }

  const vTableOwnershipModuleDeployment = await deploy('VTableOwnershipModule', {
    from: deployer,
    args: [],
    log: true,
    ...(await getGasPrice()),
  });

  const vTableUpdateModuleDeployment = await deploy('VTableUpdateModule', {
    from: deployer,
    args: [],
    log: true,
    ...(await getGasPrice()),
  });

  const viewerDeployment = await deploy('Viewer', {
    from: deployer,
    contract: 'VTableProxy',
    args: [vTableUpdateModuleDeployment.address],
    log: true,
    ...(await getGasPrice()),
  });

  const gardenViewerModuleDeployment = await deploy('GardenViewer', {
    from: deployer,
    args: [controller.address],
    log: true,
    ...(await getGasPrice()),
  });

  const heartViewerModuleDeployment = await deploy('HeartViewer', {
    from: deployer,
    args: [controller.address, governor.address, heart.address, HEART_GARDEN_ADDRES],
    log: true,
    ...(await getGasPrice()),
  });

  const vTableProxyContract = await ethers.getContractAt('VTableUpdateModule', viewerDeployment.address, signer);

  if (vTableUpdateModuleDeployment.newlyDeployed) {
    const vTableOwnershipModuleContract = await ethers.getContractAt(
      'VTableOwnershipModule',
      vTableUpdateModuleDeployment.address,
      signer,
    );
    const sigs = Object.keys(vTableOwnershipModuleContract.interface.functions).map((func) =>
      vTableOwnershipModuleContract.interface.getSighash(func),
    );
    await vTableProxyContract.updateVTable([[vTableOwnershipModuleDeployment.address, sigs]]);
  }

  if (gardenViewerModuleDeployment.newlyDeployed) {
    const gardenModuleViewerContract = await ethers.getContractAt(
      'GardenViewer',
      gardenViewerModuleDeployment.address,
      signer,
    );
    const sigs = Object.keys(gardenModuleViewerContract.interface.functions).map((func) =>
      gardenModuleViewerContract.interface.getSighash(func),
    );
    await vTableProxyContract.updateVTable([[gardenViewerModuleDeployment.address, sigs]]);
  }

  if (heartViewerModuleDeployment.newlyDeployed) {
    const heartViewerModuleContract = await ethers.getContractAt(
      'HeartViewer',
      heartViewerModuleDeployment.address,
      signer,
    );
    const sigs = Object.keys(heartViewerModuleContract.interface.functions).map((func) =>
      heartViewerModuleContract.interface.getSighash(func),
    );
    await vTableProxyContract.updateVTable([[heartViewerModuleDeployment.address, sigs]]);
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['BabViewer'];
