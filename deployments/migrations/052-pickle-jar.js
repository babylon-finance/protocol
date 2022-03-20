module.exports = async ({
  network,
  getTenderlyContract,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getGasPrice,
}) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const contract = 'PickleJarIntegration';

  const controller = await deployments.get('BabControllerProxy');

  console.log('deploy', controller.address);
  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address],
    log: true,
    ...(await getGasPrice()),
  });
  if (deployment.newlyDeployed) {
    console.log(`Adding pickle jar integration ${contract}(${deployment.address})`);
  }
  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['PickleJar'];
