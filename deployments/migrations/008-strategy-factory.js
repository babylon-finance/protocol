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
  const gasData = await getGasPrice();

  const strategyFactoryContract = 'StrategyFactory';
  const strategyContract = 'Strategy';
  const beaconContract = 'StrategyBeacon';

  const controller = await getController();

  const strategy = await deploy(strategyContract, {
    from: deployer,
    args: [],
    log: true,
    ...gasData,
  });

  const beacon = await deploy(beaconContract, {
    from: deployer,
    contract: 'UpgradeableBeacon',
    args: [strategy.address],
    log: true,
    ...gasData,
  });

  const strategyFactory = await deploy(strategyFactoryContract, {
    from: deployer,
    args: [controller.address, beacon.address],
    log: true,
    ...gasData,
  });

  if (strategyFactory.newlyDeployed) {
    console.log(`Setting strategy factory on controller ${strategyFactory.address}`);
    await (await controller.editStrategyFactory(strategyFactory.address, { ...gasData })).wait();
  }

  if (network.live && strategy.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(strategyContract));
  }

  if (network.live && beacon.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(beaconContract));
  }

  if (network.live && strategyFactory.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(strategyFactoryContract));
  }
};

module.exports.tags = ['StrategyFactory'];
