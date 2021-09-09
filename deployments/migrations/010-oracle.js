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

  const controller = await deployments.get('BabControllerProxy');
  const controllerContract = await ethers.getContractAt('BabController', controller.address, signer);
  const contract = 'PriceOracle';

  const deployment = await deploy(contract, {
    from: deployer,
    args: [],
    log: true,
    gasPrice,
  });

  if (deployment.newlyDeployed) {
  //  console.log(`Setting price oracle on controller ${deployment.address}`);
  //  const isDeployer = (await controllerContract.owner()) === deployer;
  //  await (
  //    await controllerContract
  //      .connect(isDeployer ? signer : await getSigner(owner))
  //      .editPriceOracle(deployment.address, { gasPrice })
  //  ).wait();
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['Oracle'];
