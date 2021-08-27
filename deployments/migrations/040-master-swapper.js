module.exports = async ({
  network,
  getTenderlyContract,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getRapid,
}) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const gasPrice = await getRapid();
  const contract = 'MasterSwapper';

  const controller = await deployments.get('BabControllerProxy');
  const curve = await deployments.get('CurveTradeIntegration');
  const univ3 = await deployments.get('UniswapV3TradeIntegration');
  const synthetix = await deployments.get('SynthetixTradeIntegration');

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, curve.address, univ3.address, synthetix.address],
    log: true,
    gasPrice,
  });
  if (deployment.newlyDeployed) {
    console.log(`Adding master swapper ${contract}(${deployment.address})`);
  }
  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['MasterSwapper'];
