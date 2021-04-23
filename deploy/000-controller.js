module.exports = async ({ getNamedAccounts, upgradesDeployer }) => {
  const { deployer } = await getNamedAccounts();

  await upgradesDeployer.deployOrUpgrade(
    'BabController',
    { from: deployer, log: true },
    {
      initializer: { method: 'initialize', args: [] },
    },
  );
};

module.exports.tags = ['Controller'];
