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
  const { deployer, owner } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const contract = 'CompoundBorrowIntegration';

  const controller = await getController();

  const deployment = await deploy(contract, {
    from: deployer,
    args: [
      'compoundborrow',
      controller.address,
      ethers.utils.parseEther('0.40'),
      '0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b',
    ],
    log: true,
    ...(await getGasPrice()),
  });

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['Compound-borrow'];
