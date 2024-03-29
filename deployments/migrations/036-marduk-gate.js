module.exports = async ({
  network,
  getTenderlyContract,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getGasPrice,
  getSigner,
  getContract,
  getConroller,
}) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const contract = 'MardukGate';

  const controller = await getController();
  const ishtarGate = await getContract('IshtarGate');

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, ishtarGate.address],
    log: true,
    ...(await getGasPrice()),
  });

  if (deployment.newlyDeployed) {
    console.log(`Setting marduk gate on controller ${deployment.address}`);
    await (await controller.editMardukGate(deployment.address, { ...(await getGasPrice()) })).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['MardukGate'];
