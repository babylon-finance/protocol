let MULTISIG = process.env.MULTISIG || '';

module.exports = async ({ getNamedAccounts, deployments, ethers, getSigner, getChainId, getContract }) => {
  const signers = await ethers.getSigners();
  const chainId = await getChainId();

  const { deployer } = await getNamedAccounts();
  const deployerSigner = await getSigner(deployer);

  if (chainId === '31337') {
    // use the third signer as MULTISIG
    MULTISIG = signers[2].address;
  } else if (!MULTISIG) {
    throw new Error('MULTISIG address is not set');
  }

  console.log('Transfer ownership of BabController');
  const babController = await getContract('BabController', 'BabControllerProxy');
  await babController.connect(deployerSigner).transferOwnership(MULTISIG);

  console.log('Transfer ownership of BABLToken');
  const bablToken = await getContract('BABLToken');
  await bablToken.connect(deployerSigner).transferOwnership(MULTISIG);

  console.log('Transfer ownership of RewardsDistributor');
  const rewardsDistributor = await getContract('RewardsDistributor');
  await rewardsDistributor.connect(deployerSigner).transferOwnership(MULTISIG);

  console.log('Transfer ownership of TimeLockRegistry');
  const timeLockRegistry = await getContract('TimeLockRegistry');
  await timeLockRegistry.connect(deployerSigner).transferOwnership(MULTISIG);

  console.log('Transfer ownership of Treasury');
  const treasury = await getContract('Treasury');
  await treasury.connect(deployerSigner).transferOwnership(MULTISIG);

  console.log('Transfer ownership of PriceOracle');
  const priceOracle = await getContract('PriceOracle');
  await priceOracle.connect(deployerSigner).transferOwnership(MULTISIG);

  console.log('Transfer ownership of IshtarGate');
  const ishtarGate = await getContract('IshtarGate');
  await ishtarGate.connect(deployerSigner).transferOwnership(MULTISIG);

  console.log('Transfer ownership of UniswapTWAP');
  const uniswapTWAP = await getContract('UniswapTWAP');
  await uniswapTWAP.connect(deployerSigner).transferOwnership(MULTISIG);
};

module.exports.tags = ['Ownership'];
module.exports.dependencies = ['Transfer'];
