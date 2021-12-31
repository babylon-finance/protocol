const addresses = require('../../lib/addresses');

module.exports = async ({
  network,
  getTenderlyContract,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getGasPrice,
  getContract,
}) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const gasPrice = await getGasPrice();

  const contract = 'TokenIdentifier';
  const deployment = await deploy(contract, {
    from: deployer,
    args: [],
    log: true,
    gasPrice,
  });

  const priceOracleContract = await getContract('PriceOracle', 'PriceOracleProxy', signer);

  if (deployment.newlyDeployed) {
    console.log(`Setting token identifier on price oracle ${deployment.address}`);
    await (await priceOracleContract.updateTokenIdentifier(deployment.address, { gasPrice })).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['TokenIdentifier'];
