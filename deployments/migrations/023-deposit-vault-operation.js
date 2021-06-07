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
  const { deployer, owner } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const gasPrice = await getRapid();
  const contract = 'DepositVaultOperation';

  const controller = await deployments.get('BabControllerProxy');
  const controllerContract = await ethers.getContractAt('BabController', controller.address, signer);

  const deployment = await deploy(contract, {
    from: deployer,
    args: ['vault', controller.address],
    log: true,
    gasPrice,
  });

  if (deployment.newlyDeployed) {
    console.log(`Adding operation ${contract}(${deployment.address}) to BabController`);
    await (await controllerContract.setOperation(2, deployment.address, { gasPrice })).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['DepositVaultOp'];
