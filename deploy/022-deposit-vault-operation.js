module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('DepositVaultOperation', {
    from: deployer,
    args: ['vault', controller.address],
    log: true,
  });
};

module.exports.tags = ['DepositVaultOp'];
module.exports.dependencies = ['AddLiquidityOp'];
