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

  const gardenFactoryName = 'GardenFactory';
  const gardenName = 'Garden';
  const adminGardenModuleName = 'AdminGardenModule';
  const beaconName = 'GardenBeacon';
  const vTableBeaconName = 'GardenVTableBeacon';

  const controller = await getController();

  const vTableBeacon = await deploy(vTableBeaconName, {
    from: deployer,
    contract: 'VTableBeacon',
    args: [],
    log: true,
    ...(await getGasPrice()),
  });

  const garden = await deploy(gardenName, {
    from: deployer,
    args: [vTableBeacon.address],
    log: true,
    ...(await getGasPrice()),
  });

  const adminGardenModule = await deploy(adminGardenModuleName, {
    from: deployer,
    args: [],
    log: true,
    ...(await getGasPrice()),
  });

  const beacon = await deploy(beaconName, {
    from: deployer,
    contract: 'UpgradeableBeacon',
    args: [garden.address],
    log: true,
    ...(await getGasPrice()),
  });

  const gardenFactory = await deploy(gardenFactoryName, {
    from: deployer,
    args: [controller.address, beacon.address],
    log: true,
    ...(await getGasPrice()),
  });

  if (gardenFactory.newlyDeployed) {
    console.log(`Setting garden factory on controller ${gardenFactory.address}`);
    await (await controller.editGardenFactory(gardenFactory.address, { ...(await getGasPrice()) })).wait();
  }

  if (adminGardenModule.newlyDeployed) {
    const adminGardenModuleContract = await ethers.getContractAt(
      adminGardenModuleName,
      adminGardenModule.address,
      signer,
    );
    const vTableBeaconContract = await ethers.getContractAt('VTableBeacon', vTableBeacon.address, signer);
    // update admin module on the beacon
    const sigs = Object.keys(adminGardenModuleContract.interface.functions).map((func) =>
      adminGardenModuleContract.interface.getSighash(func),
    );
    await vTableBeaconContract.updateVTable([[adminGardenModule.address, sigs]]);
  }

  if (network.live && garden.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(gardenName));
  }

  if (network.live && beacon.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(beaconName));
  }

  if (network.live && gardenFactory.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(gardenFactoryName));
  }
};

module.exports.tags = ['GardenFactory'];
