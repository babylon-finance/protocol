const { eth } = require('lib/helpers');

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
  const { deploy } = deployments;
  const { deployer, owner } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const gasPrice = await getGasPrice();

  const controller = await getController();

  const heart = await upgradesDeployer.deployAdminProxy(
    'Heart',
    'HeartProxy',
    { from: deployer, log: true, gasPrice },
    {
      initializer: {
        method: 'initialize',
        args: [controller.address, [eth('0.50'), eth('0.20'), eth('0.20'), eth('0.10')]],
      },
    },
  );

  if (heart.newlyDeployed) {
    console.log(`Setting heart on controller ${heart.address}`);
    await (await controller.editHeart(heart.address, { gasPrice })).wait();
  }

  if (network.live && heart.newlyDeployed) {
    // fails, mostly likely because of the usage of libs
    await tenderly.push(await getTenderlyContracts(['Heart', 'HeartProxy']));
  }
};

module.exports.tags = ['Heart'];