const addresses = require('../../lib/addresses');

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
  const { deployer } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const contract = 'FuseLendIntegration';

  const controller = await getController();

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, '0xC7125E3A2925877C7371d579D29dAe4729Ac9033'],
    log: true,
    ...(await getGasPrice()),
  });

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['FuseLend'];
