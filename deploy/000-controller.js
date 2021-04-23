module.exports = async ({ getNamedAccounts, deployments, upgrades }) => {
  const { deployer } = await getNamedAccounts();

  await upgrades.deployOrUpgrade(
    'BabController',
    { from: deployer, log: true },
    {
      initializer: { method: 'initialize', args: [] },
    },
  );
};

module.exports.tags = ['Controller'];
