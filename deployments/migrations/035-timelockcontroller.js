const { ONE_DAY_IN_SECONDS, ADDRESS_ZERO } = require('../../lib/constants');

module.exports = async ({ getTenderlyContract, getNamedAccounts, deployments, getGasPrice, network, tenderly }) => {
  const { deployer } = await getNamedAccounts();
  const { maxPriorityFeePerGas } = await getGasPrice();
  const { deploy } = deployments;

  const timelockController = await deploy('TimelockController', {
    from: deployer,
    args: [ONE_DAY_IN_SECONDS, [], []],
    log: true,
    maxPriorityFeePerGas,
  });
  console.log('Deployed TimelockController at', timelockController.address);

  if (network.live && timelockController.newlyDeployed) {
    const contract = await getTenderlyContract('TimelockController');
    await tenderly.push(contract);
  }
};

module.exports.tags = ['TimelockController'];
