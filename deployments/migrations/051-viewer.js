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
  async function registerModule(deployment, name, proxy) {
    console.log(`Updating ${name}...`);
    if (true || deployment.newlyDeployed) {
      const contract = await ethers.getContractAt(name, deployment.address, signer);
      const sigs = Object.keys(contract.interface.functions).map((func) => contract.interface.getSighash(func));
      const tx = await proxy.updateVTable([[deployment.address, sigs]]);
      console.log(`Tx hash ${tx.hash}`);
      await tx.wait();
    }
  }

  async function deployAndPush(name, args, contract) {
    const deployment = await deploy(name, {
      from: deployer,
      contract,
      args,
      log: true,
      ...(await getGasPrice()),
    });

    if (network.live && deployment.newlyDeployed) {
      await tenderly.push(await getTenderlyContract(name));
    }
    return deployment;
  }

  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await getSigner(deployer);

  const controller = await deployments.get('BabControllerProxy');
  const governor = await deployments.get('BabylonGovernor');
  const heart = await deployments.get('HeartProxy');

  const vTableOwnershipModuleDeployment = await deployAndPush('VTableOwnershipModule', []);
  const vTableUpdateModuleDeployment = await deployAndPush('VTableUpdateModule', []);
  const viewerDeployment = await deployAndPush('Viewer', [vTableUpdateModuleDeployment.address], 'VTableProxy');
  const strategyViewerModuleDeployment = await deployAndPush('StrategyViewer', [controller.address]);
  const gardenViewerModuleDeployment = await deployAndPush('GardenViewer', [controller.address]);
  const heartViewerModuleDeployment = await deployAndPush('HeartViewer', [
    controller.address,
    governor.address,
    heart.address,
  ]);

  const vTableProxyContract = await ethers.getContractAt('VTableUpdateModule', viewerDeployment.address, signer);

  await registerModule(vTableUpdateModuleDeployment, 'VTableOwnershipModule', vTableProxyContract);
  await registerModule(gardenViewerModuleDeployment, 'GardenViewer', vTableProxyContract);
  await registerModule(heartViewerModuleDeployment, 'HeartViewer', vTableProxyContract);
  await registerModule(strategyViewerModuleDeployment, 'StrategyViewer', vTableProxyContract);
};

module.exports.tags = ['Viewer'];
