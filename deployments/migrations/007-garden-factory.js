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

  const gardenFactoryContract = 'GardenFactory';
  const gardenContract = 'Garden';
  const beaconContract = 'GardenBeacon';

  const controller = await deployments.get('BabControllerProxy');

  const garden = await deploy(gardenContract, {
    from: deployer,
    args: [],
    log: true,
    gasPrice,
  });

  const beacon = await deploy(beaconContract, {
    from: deployer,
    contract: 'UpgradeableBeacon',
    args: [garden.address],
    log: true,
    gasPrice,
  });

  const gardenFactory = await deploy(gardenFactoryContract, {
    from: deployer,
    args: [controller.address, beacon.address],
    log: true,
    gasPrice,
  });

  if (network.live && garden.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(gardenContract));
  }

  if (network.live && beacon.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(beaconContract));
  }

  if (network.live && gardenFactory.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(gardenFactoryContract));
  }
};

module.exports.tags = ['GardenFactory'];
module.exports.dependencies = ['Controller'];
