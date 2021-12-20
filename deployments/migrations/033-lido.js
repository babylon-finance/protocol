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
  const contract = 'LidoStakeIntegration';

  const controller = await getController();

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address],
    log: true,
    gasPrice,
  });

  if (network.live && deployment.newlyDeployed) {
    console.log(`Adding lido stake integration ${contract}(${deployment.address})`);

    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['Lido'];
