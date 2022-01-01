const addresses = require('../../lib/addresses');
const { ethers } = require('ethers');

module.exports = async ({
  network,
  getTenderlyContracts,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getGasPrice,
  getController,
}) => {
  const { deployer } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const gasPrice = await getGasPrice();
  const controller = await getController();

  const deployment = await upgradesDeployer.deployAdminProxy(
    'PriceOracle',
    'PriceOracleProxy',
    { from: deployer, log: true, gasPrice },
    {
      initializer: { method: 'initialize', args: [ethers.constants.AddressZero, controller] },
    },
  );

  if (deployment.newlyDeployed) {
    console.log(`Setting price oracle on controller ${deployment.address}`);
    await (await controller.editPriceOracle(deployment.address, { gasPrice })).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContracts(['PriceOracle', 'PriceOracleProxy']));
  }
};

module.exports.tags = ['Oracle'];
