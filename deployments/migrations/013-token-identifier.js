const addresses = require('../../lib/addresses');

module.exports = async ({
  network,
  getTenderlyContract,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getGasPrice,
  getContract,
  getController,
}) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const controller = await getController();
  const pickle = await deployments.get('PickleJarRegistry');
  const yearn = await deployments.get('YearnVaultRegistry');
  const curve = await deployments.get('CurveMetaRegistry');
  const convex = await deployments.get('ConvexRegistry');

  const contract = 'TokenIdentifier';
  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, pickle.address, yearn.address, curve.address, convex.address],
    log: true,
    ...(await getGasPrice()),
  });

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['TokenIdentifier'];
