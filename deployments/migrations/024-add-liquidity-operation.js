module.exports = async ({
  network,
  getTenderlyContract,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getRapid,
  getController,
}) => {
  const { deploy } = deployments;
  const { deployer, owner } = await getNamedAccounts();
  const gasPrice = await getRapid();
  const signer = await getSigner(deployer);
  const contract = 'AddLiquidityOperation';

  const controller = await getController();

  const deployment = await deploy(contract, {
    from: deployer,
    args: ['lp', controller.address],
    log: true,
    gasPrice,
  });

  if (deployment.newlyDeployed) {
    console.log(`Adding operation ${contract}(${deployment.address}) to BabController`);
    await (await controller.setOperation(1, deployment.address, { gasPrice })).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['AddLiquidityOp'];
