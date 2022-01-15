const addresses = require('../../lib/addresses');
const { ethers } = require('ethers');

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
  const controller = await getController();
  const oracle = await deployments.get('TokenIdentifier');

  const deployment = await deploy('PriceOracle', {
    from: deployer,
    args: [oracle.address, controller.address],
    log: true,
    gasPrice,
  });

  if (deployment.newlyDeployed) {
    console.log(`Setting price oracle on controller ${deployment.address}`);
    await (await controller.editPriceOracle(deployment.address, { gasPrice })).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract('PriceOracle'));
  }
};

module.exports.tags = ['Oracle'];
