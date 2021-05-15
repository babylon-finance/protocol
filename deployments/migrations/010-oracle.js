const addresses = require('../../lib/addresses');

module.exports = async ({ getNamedAccounts, deployments, ethers, getRapid }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const controller = await deployments.get('BabControllerProxy');
  const TWAP = await deployments.get('UniswapTWAP');

  const uniswapTWAPv3 = await deployments.get('UniswapTWAPV3');

  await deploy('PriceOracle', {
    from: deployer,
    args: [controller.address, addresses.compound.OpenOracle, [TWAP.address, uniswapTWAPv3.address]],
    log: true,
    gasPrice,
  });
};

module.exports.tags = ['Oracle'];
