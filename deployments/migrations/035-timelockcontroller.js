const { ONE_DAY_IN_SECONDS, ADDRESS_ZERO } = require('../../lib/constants');

module.exports = async ({ getTenderlyContract, getNamedAccounts, deployments, getRapid, network, tenderly }) => {
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();
  const { deploy } = deployments;

  const proposer = [deployer];
  const executor = [deployer];

  const timelockController = await deploy('TimelockController', {
    from: deployer,
    args: [ONE_DAY_IN_SECONDS, proposer, executor],
    log: true,
    gasPrice,
  });
  console.log('Deployed TimelockController at', timelockController.address);

  if (network.live && timelockController.newlyDeployed) {
    const contract = await getTenderlyContract('TimelockController');
    await tenderly.push(contract);
  }
};

module.exports.tags = ['TimelockController'];
