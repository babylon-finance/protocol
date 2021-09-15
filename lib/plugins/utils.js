const { extendEnvironment } = require('hardhat/config');

extendEnvironment((hre) => {
  hre.getContract = async (contractName, deploymentName, signer) => {
    return await ethers.getContractAt(
      contractName,
      (await deployments.get(deploymentName || contractName)).address,
      signer,
    );
  };

  hre.getSigner = async (address) => {
    const signers = await ethers.getSigners();
    return signers.find((signer) => signer.address === address);
  };

  hre.getTenderlyContract = async (contract) => {
    return {
      name: contract,
      address: (await hre.deployments.get(contract)).address,
    };
  };

  hre.getController = async () => {
    const { getNamedAccounts } = hre;
    const { deployer, owner } = await getNamedAccounts();
    const signer = await getSigner(deployer);
    const controller = await ethers.getContractAt('BabController', (await deployments.get('BabControllerProxy')).address, signer);
    const isDeployer = (await controller.owner()) === deployer;
    return controller.connect(isDeployer ? signer : await getSigner(owner));
  };

  hre.getTenderlyContracts = async (contracts) => {
    return await Promise.all(contracts.map((contract) => hre.getTenderlyContract(contract)));
  };
});
