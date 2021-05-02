module.exports = async ({ getNamedAccounts, deployments, ethers, getRapid }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('BuyOperation', {
    from: deployer,
    args: ['buy', controller.address],
    log: true,
    gasPrice,
  });
};

module.exports.tags = ['BuyOp'];
module.exports.dependencies = ['Aave'];
