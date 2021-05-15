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

  const controller = await deployments.get('BabControllerProxy');
  const TWAP = await deployments.get('UniswapTWAP');
  const contract = 'PriceOracle';

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, addresses.compound.OpenOracle, [TWAP.address]],
    log: true,
    gasPrice,
  });

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['Oracle'];
