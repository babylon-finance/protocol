module.exports = async ({
  network,
  getTenderlyContract,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getGasPrice,
  getChainId,
  getController,
}) => {
  const { deploy } = deployments;
  const { deployer, owner } = await getNamedAccounts();

  const signer = await getSigner(deployer);
  const chainId = await getChainId();

  const gardenFactoryName = 'GardenFactory';
  const gardenName = 'Garden';
  const adminGardenModuleName = 'AdminGardenModule';
  const strategyGardenModuleName = 'StrategyGardenModule';
  const beaconName = 'GardenBeacon';
  const vTableBeaconName = 'GardenVTableBeacon';

  const controller = await getController();

  const bablToken = await deployments.get('BABLToken');
  const BABL = bablToken.address;

  if (chainId === '1') {
    BABL = '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74';
  }

  const vTableBeacon = await deploy(vTableBeaconName, {
    from: deployer,
    contract: 'VTableBeacon',
    args: [],
    log: true,
    ...(await getGasPrice()),
  });

  const garden = await deploy(gardenName, {
    from: deployer,
    args: [vTableBeacon.address, BABL],
    log: true,
    ...(await getGasPrice()),
  });

  const adminGardenModule = await deploy(adminGardenModuleName, {
    from: deployer,
    args: [],
    log: true,
    ...(await getGasPrice()),
  });

  const strategyGardenModule = await deploy(strategyGardenModuleName, {
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
  const vTableBeaconContract = await ethers.getContractAt('VTableBeacon', vTableBeacon.address, signer);

  if (strategyGardenModule.newlyDeployed) {
    const strategyGardenModuleContract = await ethers.getContractAt(
      strategyGardenModuleName,
      strategyGardenModule.address,
      signer,
    );
    // update admin module on the beacon
    const sigs = Object.keys(strategyGardenModuleContract.interface.functions).map((func) =>
      strategyGardenModuleContract.interface.getSighash(func),
    );
    await vTableBeaconContract.updateVTable([[strategyGardenModule.address, sigs]]);
  }

  if (adminGardenModule.newlyDeployed) {
    const adminGardenModuleContract = await ethers.getContractAt(
      adminGardenModuleName,
      adminGardenModule.address,
      signer,
    );
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
