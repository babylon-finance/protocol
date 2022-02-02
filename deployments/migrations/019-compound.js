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
  const gasPrice = await getGasPrice();
  const contract = 'CompoundLendIntegration';

  const controller = await getController();

  const deployment = await deploy(contract, {
    from: deployer,
    args: ['compoundlend', controller.address, '0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b'],
    log: true,
    gasPrice,
  });

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['CompoundLend'];
