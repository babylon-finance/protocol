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
  const { deployer, owner } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const gasPrice = await getRapid();
  const contract = 'UniswapV3TradeIntegration';

  const controller = await deployments.get('BabControllerProxy');
  const controllerContract = await ethers.getContractAt('IBabController', controller.address, signer);

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address],
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

    console.log('Setting default trade integration', deployment.address);
    await (await controllerContract.setDefaultTradeIntegration(deployment.address, { gasPrice })).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['UniV3Trade'];
