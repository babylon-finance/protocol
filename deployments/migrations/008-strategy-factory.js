module.exports = async ({
  network,
  getTenderlyContract,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getRapid,
}) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const strategyFactoryContract = 'StrategyFactory';
  const strategyContract = 'Strategy';
  const beaconContract = 'StrategyBeacon';

  const controller = await deployments.get('BabControllerProxy');

  const strategy = await deploy(strategyContract, {
    from: deployer,
    args: [],
    log: true,
    gasPrice,
  });

  const beacon = await deploy(beaconContract, {
    from: deployer,
    contract: 'UpgradeableBeacon',
    args: [strategy.address],
    log: true,
    gasPrice,
  });

  const strategyFactory = await deploy(strategyFactoryContract, {
    from: deployer,
    args: [controller.address, beacon.address],
    log: true,
    gasPrice,
  });

  if (network.live && strategy.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(strategyContract));
  }

  if (network.live && strategyFactory.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(beaconContract));
  }

  if (network.live && strategyFactory.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(strategyFactoryContract));
  }
};

module.exports.tags = ['StrategyFactory'];
