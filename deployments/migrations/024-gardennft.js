module.exports = async ({ getNamedAccounts, deployments, ethers, getRapid }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('GardenNFT', {
    from: deployer,
    args: [controller.address, 'Babylon Garden NFT', 'GARDEN_NFT'],
    log: true,
    gasPrice,
  });
};

module.exports.tags = ['GardenNFT'];
