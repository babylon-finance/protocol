let MULTISIG = process.env.MULTISIG || '';

const addresses = require('../../lib/addresses');

module.exports = async ({ getNamedAccounts, deployments, ethers, getSigner, getContract, getChainId, getRapid }) => {
  const signers = await ethers.getSigners();
  const { deploy } = deployments;
  const chainId = await getChainId();
  const { deployer } = await getNamedAccounts();
  const deployerSigner = await getSigner(deployer);
  const gasPrice = await getRapid();

  if (chainId === '31337') {
    // use the third signer as MULTISIG
    MULTISIG = signers[2].address;
  } else if (!MULTISIG) {
    throw new Error('MULTISIG address is not set');
  }

  const controller = await deployments.get('BabControllerProxy');

  await deploy('UniswapTWAPV3', {
    from: deployer,
    args: [controller.address, addresses.uniswap.v3.factory],
    log: true,
    gasPrice,
  });

  console.log('Transfer ownership of UniswapTWAP');
  const uniswapTWAPv3 = await getContract('UniswapTWAPV3');
  await uniswapTWAPv3.connect(deployerSigner).transferOwnership(MULTISIG, { gasPrice });

  const priceOracle = await getContract('PriceOracle');
  await priceOracle.connect(deployerSigner).addAdapter(uniswapTWAPv3.address, { gasPrice });
};

module.exports.tags = ['UniswapTWAPV3'];
