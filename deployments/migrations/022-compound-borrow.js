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
  const contract = 'CompoundBorrowIntegration';

  const controller = await deployments.get('BabControllerProxy');
  const controllerContract = await ethers.getContractAt('IBabController', controller.address, signer);

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, ethers.utils.parseEther('0.30')],
    log: true,
    gasPrice,
  });

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['Compound-borrow'];
