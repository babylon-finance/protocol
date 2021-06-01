module.exports = async ({
  getNamedAccounts,
  deployments,
  upgradesDeployer,
  getRapid,
  network,
  tenderly,
  getTenderlyContracts,
}) => {
  const { deployer, owner } = await getNamedAccounts();
  const gasPrice = await getRapid();

  console.log('network.live', network.live);
  const controller = await upgradesDeployer.deployOrUpgrade(
    'BabController',
    { from: deployer, log: true, gasPrice },
    {
      initializer: { method: 'initialize', args: [] },
      upgrades: network.live ? ['BabControllerV2'] : [],
    },
  );

  if (network.live && controller.newlyDeployed) {
    const contracts = await getTenderlyContracts(['BabController', 'BabControllerProxy', 'ProxyAdmin']);
    await tenderly.push(contracts);
  }
};

module.exports.tags = ['Controller'];
