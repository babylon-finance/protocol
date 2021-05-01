module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('LendOperation', {
    from: deployer,
    args: ['lend', controller.address],
    log: true,
  });
};

module.exports.tags = ['LendOp'];
module.exports.dependencies = ['DepositVaultOp'];
