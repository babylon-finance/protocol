module.exports = async ({ getNamedAccounts, deployments, myPlugin }) => {
  const { deployer } = await getNamedAccounts();

  await myPlugin.deployOrUpgrade(
    'BabController',
    { from: deployer, log: true },
    {
      initializer: { method: 'initialize', args: [] },
    },
  );
};

module.exports.tags = ['Controller'];
