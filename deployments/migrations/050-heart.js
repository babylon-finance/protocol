const { eth } = require('lib/helpers');

module.exports = async ({
  network,
  getTenderlyContracts,
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

  const heart = await upgradesDeployer.deployAdminProxy(
    'Heart',
    'HeartProxy',
    {
      from: deployer,
      log: true,
      ...(await getGasPrice()),
      args: [controller.address, (await deployments.get('BabylonGovernor')).address],
    },
    {
      initializer: {
        method: 'initialize',
        args: [[eth(0.1), eth(0.3), eth(0.25), eth(0.15), eth(0.2), eth(0.05)]],
      },
    },
  );

  if (heart.newlyDeployed) {
    console.log(`Setting heart on controller ${heart.address}`);
    await (await controller.editHeart(heart.address, { ...(await getGasPrice()) })).wait();
  }

  if (network.live && heart.newlyDeployed) {
    // fails, mostly likely because of the usage of libs
    await tenderly.push(await getTenderlyContracts(['Heart', 'HeartProxy']));
  }
};

module.exports.tags = ['Heart'];
