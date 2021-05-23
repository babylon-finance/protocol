const fs = require('fs-extra');

async function exportContracts(contracts, prefix = '/contracts/') {
  const contractsObj = JSON.parse(fs.readFileSync('./contracts.json'));
  for (const contract of contracts) {
    const contractObj = JSON.parse(fs.readFileSync(`./artifacts${prefix}${contract}`));
    contractsObj.contracts[contractObj.contractName] = {
      address: contractObj.address,
      abi: contractObj.abi,
      bytecode: contractObj.bytecode,
    };
  }
  // Delete bytecode from each contract
  for (const key of Object.keys(contractsObj.contracts)) {
    delete contractsObj.contracts[key].bytecode;
  }
  fs.outputJsonSync('./contracts.json', contractsObj);
}

module.exports = {
  exportContracts,
};
