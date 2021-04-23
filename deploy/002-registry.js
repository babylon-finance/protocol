module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const bablToken = await deployments.get('BABLToken');

  const timeLockRegistry = await deploy('TimeLockRegistry', {
    from: deployer,
    args: [bablToken.address],
    log: true,
  });

  const bablTokenContract = await ethers.getContractAt('BABLToken', bablToken.address);
  // Sets the Time Lock Registry address
  await bablTokenContract.setTimeLockRegistry(timeLockRegistry.address);
  console.log(`Set time lock registry on BABL token to ${timeLockRegistry.address}`);

  // Approve Time Lock Registry to handle 31% of the Tokens for vesting (Team, Advisors, Investors)
  await bablTokenContract.approve(timeLockRegistry.address, ethers.utils.parseEther('310000'));
};

module.exports.tags = ['Registry'];
module.exports.dependencies = ['Token'];
