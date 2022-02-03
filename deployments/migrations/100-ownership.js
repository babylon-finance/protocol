let MULTISIG = process.env.MULTISIG || '';

module.exports = async ({
  network,
  getNamedAccounts,
  deployments,
  ethers,
  getSigner,
  getChainId,
  getContract,
  getGasPrice,
}) => {
  const signers = await ethers.getSigners();
  const chainId = await getChainId();
  const { maxPriorityFeePerGas } = await getGasPrice();

  const { deployer, owner } = await getNamedAccounts();
  const signer = await getSigner(deployer);

  if (chainId === '31337') {
    // use the third signer as MULTISIG
    MULTISIG = signers[2].address;
  } else if (!MULTISIG) {
    throw new Error('MULTISIG address is not set');
  }

  const timelock = await deployments.get('TimelockController');
  const timelockAddress = timelock.address;

  const proxyAdminDeployment = await deployments.get('ProxyAdmin');
  const proxyAdmin = new ethers.Contract(proxyAdminDeployment.address, proxyAdminDeployment.abi, signer);
  if ((await proxyAdmin.owner()) !== timelockAddress) {
    console.log('Transfer ownership of ProxyAdmin');
    await (await proxyAdmin.transferOwnership(timelockAddress, { maxPriorityFeePerGas })).wait();
  }

  let deployment = await deployments.get('GardenBeacon');
  let contract = new ethers.Contract(deployment.address, deployment.abi, signer);
  if ((await contract.owner()) !== timelockAddress) {
    console.log(`Transfer ownership of GardenBeacon to ${timelockAddress}`);
    await (await contract.transferOwnership(timelockAddress, { maxPriorityFeePerGas })).wait();
  }

  deployment = await deployments.get('StrategyBeacon');
  contract = new ethers.Contract(deployment.address, deployment.abi, signer);
  if ((await contract.owner()) !== timelockAddress) {
    console.log(`Transfer ownership of StrategyBeacon to ${timelockAddress}`);
    await (await contract.transferOwnership(timelockAddress, { maxPriorityFeePerGas })).wait();
  }

  for (const entry of [
    ['BabController', 'BabControllerProxy'],
    ['PriceOracle', ''],
    ['BABLToken', ''],
    ['RewardsDistributor', 'RewardsDistributorProxy'],
    ['Treasury', ''],
    ['TimeLockRegistry', ''],
    ['IshtarGate', ''],
    ['MardukGate', ''],
    ['Heart', 'HeartProxy'],
  ]) {
    const contract = await getContract(entry[0], entry[1], signer);
    if ((await contract.owner()) !== timelockAddress && entry[0] !== 'TimeLockRegistry') {
      console.log(`Transfer ownership of ${entry[0]} to ${timelockAddress}`);
      await (await contract.transferOwnership(timelockAddress, { maxPriorityFeePerGas })).wait();
    } else if (entry[0] === 'TimeLockRegistry') {
      console.log(`Transfer ownership of ${entry[0]} to ${MULTISIG}`);
      await (await contract.transferOwnership(MULTISIG, { maxPriorityFeePerGas })).wait();
    }
  }
};

module.exports.tags = ['Ownership'];
