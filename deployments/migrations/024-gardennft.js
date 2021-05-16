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
  const gasPrice = await getRapid();
  const contract = 'GardenNFT';

  const controller = await deployments.get('BabControllerProxy');

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, 'Babylon Garden NFT', 'GARDEN_NFT'],
    log: true,
    gasPrice,
  });

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['GardenNFT'];
