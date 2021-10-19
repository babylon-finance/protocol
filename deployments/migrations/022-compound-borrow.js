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
  const gasPrice = await getGasPrice();
  const contract = 'CompoundBorrowIntegration';

  const controller = await getController();

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, ethers.utils.parseEther('0.30')],
    log: true,
    gasPrice,
  });

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['Compound-borrow'];
