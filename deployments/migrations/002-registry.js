module.exports = async ({
  tenderly,
  getTenderlyContract,
  network,
  getNamedAccounts,
  deployments,
  ethers,
  getRapid,
}) => {
  const { deploy } = deployments;
  const { deployer, owner } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const gasPrice = await getRapid();

  const bablToken = await deployments.get('BABLToken');

  const timeLockRegistry = await deploy('TimeLockRegistry', {
    from: deployer,
    args: [bablToken.address],
    log: true,
    gasPrice,
  });

  if (timeLockRegistry.newlyDeployed) {
    const bablTokenContract = await ethers.getContractAt('BABLToken', bablToken.address);
    const isDeployer = (await bablTokenContract.owner()) === deployer;
    console.log('Setting TimeLockRegistry on BABLToken');
    await bablTokenContract
      .connect(isDeployer ? signer : await getSigner(owner))
      .setTimeLockRegistry(timeLockRegistry.address);
  }

  if (network.live && timeLockRegistry.newlyDeployed) {
    const contract = await getTenderlyContract('TimeLockRegistry');
    await tenderly.push(contract);
  }
};

module.exports.tags = ['Registry'];
