let MULTISIG = process.env.MULTISIG || '';

module.exports = async ({ getNamedAccounts, deployments, ethers, getSigner, getChainId, getContract, getRapid }) => {
  const signers = await ethers.getSigners();
  const chainId = await getChainId();
  const gasPrice = await getRapid();

  const { deployer } = await getNamedAccounts();
  const signer = await getSigner(deployer);

  if (chainId === '31337') {
    // use the third signer as MULTISIG
    MULTISIG = signers[2].address;
  } else if (!MULTISIG) {
    throw new Error('MULTISIG address is not set');
  }


  console.log('Transfer ownership of ProxyAdmin');
  const proxyAdminDeployment = await deployments.get('ProxyAdmin');
  const proxyAdmin = new ethers.Contract(proxyAdminDeployment.address, proxyAdminDeployment.abi);
  await (await proxyAdmin.connect(signer).transferOwnership(MULTISIG, { gasPrice })).wait();

  console.log('Transfer ownership of GardenBeacon');
  let deployment = await deployments.get('GardenBeacon');
  let contract = new ethers.Contract(deployment.address, deployment.abi);
  await (await contract.connect(signer).transferOwnership(MULTISIG, { gasPrice })).wait();

  console.log('Transfer ownership of StrategyBeacon');
  deployment = await deployments.get('StrategyBeacon');
  contract = new ethers.Contract(deployment.address, deployment.abi);
  await (await contract.connect(signer).transferOwnership(MULTISIG, { gasPrice })).wait();

  console.log('Transfer ownership of BabController');
  const babController = await getContract('BabController', 'BabControllerProxy');
  await (await babController.connect(signer).transferOwnership(MULTISIG, { gasPrice })).wait();

  console.log('Transfer ownership of BABLToken');
  const bablToken = await getContract('BABLToken');
  await (await bablToken.connect(signer).transferOwnership(MULTISIG, { gasPrice })).wait();

  console.log('Transfer ownership of RewardsDistributor');
  const rewardsDistributor = await getContract('RewardsDistributor', 'RewardsDistributorProxy');
  await (await rewardsDistributor.connect(signer).transferOwnership(MULTISIG, { gasPrice })).wait();

  console.log('Transfer ownership of TimeLockRegistry');
  const timeLockRegistry = await getContract('TimeLockRegistry');
  await (await timeLockRegistry.connect(signer).transferOwnership(MULTISIG, { gasPrice })).wait();

  console.log('Transfer ownership of Treasury');
  const treasury = await getContract('Treasury');
  await (await treasury.connect(signer).transferOwnership(MULTISIG, { gasPrice })).wait();

  console.log('Transfer ownership of PriceOracle');
  const priceOracle = await getContract('PriceOracle');
  await (await priceOracle.connect(signer).transferOwnership(MULTISIG, { gasPrice })).wait();

  console.log('Transfer ownership of IshtarGate');
  const ishtarGate = await getContract('IshtarGate');
  await (await ishtarGate.connect(signer).transferOwnership(MULTISIG, { gasPrice })).wait();

  console.log('Transfer ownership of UniswapTWAP v3');
  const uniswapTWAPv3 = await getContract('UniswapTWAPV3');
  await (await uniswapTWAPv3.connect(signer).transferOwnership(MULTISIG, { gasPrice })).wait();
};

module.exports.tags = ['Ownership'];
