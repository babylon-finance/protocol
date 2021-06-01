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
  const contract = 'StrategyNFT';

  const controller = await deployments.get('BabControllerProxy');
  const controllerContract = await ethers.getContractAt('BabController', controller.address, singer);

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, 'Babylon Strategy NFT', 'STRAT_NFT'],
    log: true,
    gasPrice,
  });

  if (deployment.newlyDeployed) {
    console.log(`Setting strategy NFT on controller ${deployment.address}`);
    await (await controllerContract.editStrategyNFT(deployment.address, { gasPrice })).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['StrategyNFT'];
