const addresses = require('../../lib/addresses');

module.exports = async ({ getNamedAccounts, deployments, ethers, getRapid }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const controller = await deployments.get('BabControllerProxy');
  const TWAP = await deployments.get('UniswapTWAP');

  await deploy('PriceOracle', {
    from: deployer,
    args: [controller.address, addresses.compound.OpenOracle, [TWAP.address]],
    log: true,
    gasPrice,
  });
};

module.exports.tags = ['Oracle'];
