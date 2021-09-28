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
  const { deployer } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const gasPrice = await getRapid();
  const contract = 'GardenNFT';

  const controller = await getController();

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, 'Babylon Garden NFT', 'GARDEN_NFT'],
    log: true,
    gasPrice,
  });

  if (deployment.newlyDeployed) {
    console.log(`Setting garden NFT on controller ${deployment.address}`);
    await (await controller.editGardenNFT(deployment.address, { gasPrice })).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['GardenNFT'];
