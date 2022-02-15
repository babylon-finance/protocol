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
  const contract = 'MasterSwapper';

  const controller = await getController();
  const curve = await deployments.get('CurveTradeIntegration');
  const univ3 = await deployments.get('UniswapV3TradeIntegration');
  const synthetix = await deployments.get('SynthetixTradeIntegration');
  const univ2 = await deployments.get('UniswapV2TradeIntegration');

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, curve.address, univ3.address, synthetix.address, univ2.address],
    log: true,
    ...(await getGasPrice()),
  });

  if (deployment.newlyDeployed) {
    console.log('Setting master swapper in controller', deployment.address);
    await (await controller.setMasterSwapper(deployment.address, { ...(await getGasPrice()) })).wait();
  }
  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['MasterSwapper'];
