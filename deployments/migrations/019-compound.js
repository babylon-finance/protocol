const addresses = require('../../lib/addresses');

module.exports = async ({
  network,
  getTenderlyContract,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getRapid,
}) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const singer = await getSigner(deployer);
  const gasPrice = await getRapid();
  const contract = 'CompoundLendIntegration';

  const controller = await deployments.get('BabControllerProxy');
  const controllerContract = await ethers.getContractAt('BabController', controller.address, singer);

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, addresses.tokens.WETH],
    log: true,
    gasPrice,
  });

  if (deployment.newlyDeployed) {
    console.log(`Adding integration ${contract}(${deployment.address}) to BabController`);
    await (
      await controllerContract.addIntegration(
        await (await ethers.getContractAt(contract, deployment.address)).getName(),
        deployment.address,
        { gasPrice },
      )
    ).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['Compound'];
