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
  const contract = 'AladdinConcentratorIntegration';
  const controller = await deployments.get('BabControllerProxy');

  const deployment = await deploy(contract, {
    from: deployer,
    args: [
      controller.address,
      '0x2b95A1Dcc3D405535f9ed33c219ab38E8d7e0884',
      '0xc8fF37F7d057dF1BB9Ad681b53Fa4726f268E0e8',
    ],
    log: true,
    ...(await getGasPrice()),
  });
  if (deployment.newlyDeployed) {
    console.log(`Adding aladdin concentrator integration ${contract}(${deployment.address})`);
  }
  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['AladdinConcentrator'];
