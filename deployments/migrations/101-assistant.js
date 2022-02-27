module.exports = async ({
  getNamedAccounts,
  deployments,
  upgradesDeployer,
  getGasPrice,
  network,
  tenderly,
  getTenderlyContracts,
}) => {
  const { deployer } = await getNamedAccounts();
  const signers = await ethers.getSigners();
  const chainId = await getChainId();
  const signer = await getSigner(deployer);

  const deployment = await upgradesDeployer.deployAdminProxy(
    'Assistant',
    'AssistantProxy',
    { from: deployer, log: true, ...(await getGasPrice()) },
    {
      initializer: { method: 'initialize', args: [] },
    },
  );

  if (network.live && deployment.newlyDeployed) {
    console.log('Verify on Etherscan');
    await hre.run('verify:verify', {
      contract: 'contracts/governance/Assistant.sol:Assistant',
      address: (await deployments.get('Assistant')).address,
      constructorArguments: [],
    });
  }
};

module.exports.tags = ['Assistant'];
