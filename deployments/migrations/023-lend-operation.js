module.exports = async ({ getNamedAccounts, deployments, ethers, getRapid }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('LendOperation', {
    from: deployer,
    args: ['lend', controller.address],
    log: true,
    gasPrice,
  });
};

module.exports.tags = ['LendOp'];
