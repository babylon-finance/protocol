module.exports = async ({ getNamedAccounts, deployments, ethers, getRapid }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('DepositVaultOperation', {
    from: deployer,
    args: ['vault', controller.address],
    log: true,
    gasPrice,
  });
};

module.exports.tags = ['DepositVaultOp'];
module.exports.dependencies = ['AddLiquidityOp'];
