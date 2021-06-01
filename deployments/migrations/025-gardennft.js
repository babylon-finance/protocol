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
  const singer = await getSigner(deployer);
  const gasPrice = await getRapid();
  const contract = 'GardenNFT';

  const controller = await deployments.get('BabControllerProxy');
  const controllerContract = await ethers.getContractAt('BabController', controller.address, singer);

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, 'Babylon Garden NFT', 'GARDEN_NFT'],
    log: true,
    gasPrice,
  });


  if (deployment.newlyDeployed) {
    console.log(`Setting garden NFT on controller ${deployment.address}`);
    await (await controllerContract.editGardenNFT(deployment.address, { gasPrice })).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['GardenNFT'];
