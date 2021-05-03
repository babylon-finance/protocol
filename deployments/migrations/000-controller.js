module.exports = async ({ getNamedAccounts, upgradesDeployer, getRapid }) => {
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  throw new Error('Already deployed');

  await upgradesDeployer.deployOrUpgrade(
    'BabController',
    { from: deployer, log: true, gasPrice },
    {
      initializer: { method: 'initialize', args: [] },
    },
  );
};

module.exports.tags = ['Controller'];
