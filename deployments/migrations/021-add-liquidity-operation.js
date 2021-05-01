module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('AddLiquidityOperation', {
    from: deployer,
    args: ['lp', controller.address],
    log: true,
  });
};

module.exports.tags = ['AddLiquidityOp'];
module.exports.dependencies = ['BuyOp'];
