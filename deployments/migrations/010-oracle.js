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
  const contract = 'PriceOracle';

  const uniswapTWAPv3 = await deployments.get('UniswapTWAPV3');

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, addresses.compound.OpenOracle, [uniswapTWAPv3.address]],
    log: true,
    gasPrice,
  });

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['Oracle'];
