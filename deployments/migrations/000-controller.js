module.exports = async ({
  getNamedAccounts,
  deployments,
  upgradesDeployer,
  getRapid,
  network,
  tenderly,
  getTenderlyContracts,
}) => {
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const controller = await upgradesDeployer.deployOrUpgrade(
    'BabController',
    { from: deployer, log: true, gasPrice },
    {
      initializer: { method: 'initialize', args: [] },
    },
  );

  if (network.live && controller.newlyDeployed) {
    const contracts = await getTenderlyContracts(['BabController', 'BabControllerProxy', 'ProxyAdmin']);
    await tenderly.push(contracts);
  }
};

module.exports.tags = ['Controller'];
