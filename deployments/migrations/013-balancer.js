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
  const signer = await getSigner(deployer);
  const gasPrice = await getRapid();
  const contract = 'BalancerIntegration'; // V1
  const contractV2 = 'BalancerV2Integration'; // V2

  const controller = await deployments.get('BabControllerProxy');
  const controllerContract = await ethers.getContractAt('BabController', controller.address, signer);

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, addresses.balancer.factory],
    log: true,
    gasPrice,
  });
  const deploymentV2 = await deploy(contractV2, {
    from: deployer,
    args: [controller.address],
    log: true,
    gasPrice,
  });

<<<<<<< HEAD
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
  if (deploymentV2.newlyDeployed) {
    console.log(`Adding integration ${contract}(${deploymentV2.address}) to BabController`);
    await (
      await controllerContract.addIntegration(
        await (await ethers.getContractAt(contractV2, deploymentV2.address)).getName(),
        deploymentV2.address,
        { gasPrice },
      )
    ).wait();
  }

=======
>>>>>>> main
  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
  if (network.live && deploymentV2.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contractV2));
  }
};

module.exports.tags = ['Balancer'];
