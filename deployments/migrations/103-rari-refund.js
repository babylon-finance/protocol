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
  const contract = 'RariRefund';

  const controller = await getController();

  const deployment = await deploy(contract, {
    from: deployer,
    args: [],
    log: true,
    ...(await getGasPrice()),
  });

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['RariRefund'];
