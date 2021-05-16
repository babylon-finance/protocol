module.exports = async ({ getNamedAccounts, deployments, ethers, getRapid }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('StrategyNFT', {
    from: deployer,
    args: [controller.address, 'Babylon Strategy NFT', 'STRAT_NFT'],
    log: true,
    gasPrice,
  });
};

module.exports.tags = ['StrategyNFT'];
