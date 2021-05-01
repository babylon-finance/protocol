module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('BuyOperation', {
    from: deployer,
    args: ['buy', controller.address],
    log: true,
  });
};

module.exports.tags = ['BuyOp'];
module.exports.dependencies = ['Aave'];
