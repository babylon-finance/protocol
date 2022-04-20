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
  const contract = 'GardenNFT';

  const controller = await getController();

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, 'Babylon Garden NFT', 'GARDEN_NFT'],
    log: true,
    ...(await getGasPrice()),
  });

  if (deployment.newlyDeployed) {
    console.log(`Setting garden NFT on controller ${deployment.address}`);
    await (await controller.editGardenNFT(deployment.address, { ...(await getGasPrice()) })).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['GardenNFT'];
