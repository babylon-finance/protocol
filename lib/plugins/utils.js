const { extendEnvironment } = require('hardhat/config');

extendEnvironment((hre) => {
  hre.getTenderlyContract = async (contract) => {
    return {
      name: contract,
      address: (await hre.deployments.get(contract)).address,
    };
  };

  hre.getTenderlyContracts = async (contracts) => {
    return await Promise.all(contracts.map((contract) => hre.getTenderlyContract(contract)));
  };
});
