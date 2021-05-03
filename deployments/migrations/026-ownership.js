let MULTISIG = process.env.MULTISIG || '';

module.exports = async ({ getNamedAccounts, deployments, ethers, getSigner, getChainId, getContract, getRapid }) => {
  const signers = await ethers.getSigners();
  const chainId = await getChainId();
  const gasPrice = await getRapid();

  const { deployer } = await getNamedAccounts();
  const deployerSigner = await getSigner(deployer);

  if (chainId === '31337') {
    // use the third signer as MULTISIG
    MULTISIG = signers[2].address;
  } else if (!MULTISIG) {
    throw new Error('MULTISIG address is not set');
  }

  const ishtarGate = await getContract('IshtarGate');
  for (const address of [
    '0x83f4622A18e38bE297e089fB055Dd5123bb0b279',
    '0x21584Cc5a52102AbB381286a5119E3be08431CfD',
    '0x71763709Da2488F75bc2DB5d194769d801e97Fa8',
    '0x908295e2be3a36021aadaaed0bbb124fd602cbf2',
    '0xFBbA8ceA4e9835B9f304d6E69905cD9403F2b606',
  ]) {
    console.log(`Setting creator permission for ${address}`);
    await ishtarGate.connect(deployerSigner).setCreatorPermissions(address, true, { gasPrice });
  }

  console.log('Transfer ownership of ProxyAdmin');
  const proxyArtifact = await deployments.getArtifact('ProxyAdmin');
  const proxyAdmin = new ethers.Contract((await deployments.get('ProxyAdmin')).address, proxyArtifact.abi);
  await proxyAdmin.connect(deployerSigner).transferOwnership(MULTISIG, { gasPrice });

  console.log('Transfer ownership of BabController');
  const babController = await getContract('BabController', 'BabControllerProxy');
  await babController.connect(deployerSigner).transferOwnership(MULTISIG, { gasPrice });

  console.log('Transfer ownership of BABLToken');
  const bablToken = await getContract('BABLToken');
  await bablToken.connect(deployerSigner).transferOwnership(MULTISIG, { gasPrice });

  console.log('Transfer ownership of RewardsDistributor');
  const rewardsDistributor = await getContract('RewardsDistributor');
  await rewardsDistributor.connect(deployerSigner).transferOwnership(MULTISIG, { gasPrice });

  console.log('Transfer ownership of TimeLockRegistry');
  const timeLockRegistry = await getContract('TimeLockRegistry');
  await timeLockRegistry.connect(deployerSigner).transferOwnership(MULTISIG, { gasPrice });

  console.log('Transfer ownership of Treasury');
  const treasury = await getContract('Treasury');
  await treasury.connect(deployerSigner).transferOwnership(MULTISIG, { gasPrice });

  console.log('Transfer ownership of PriceOracle');
  const priceOracle = await getContract('PriceOracle');
  await priceOracle.connect(deployerSigner).transferOwnership(MULTISIG, { gasPrice });

  console.log('Transfer ownership of IshtarGate');
  await ishtarGate.connect(deployerSigner).transferOwnership(MULTISIG, { gasPrice });

  console.log('Transfer ownership of UniswapTWAP');
  const uniswapTWAP = await getContract('UniswapTWAP');
  await uniswapTWAP.connect(deployerSigner).transferOwnership(MULTISIG, { gasPrice });
};

module.exports.tags = ['Ownership'];
