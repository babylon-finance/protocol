const addresses = require('../../lib/addresses');

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
  const gasPrice = await getRapid();
  const contract = 'YearnVaultIntegration';

  const controller = await deployments.get('BabControllerProxy');

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, addresses.tokens.WETH, addresses.yearn.vaultRegistry],
    log: true,
    gasPrice,
  });

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['Yearn'];
