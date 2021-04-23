const fs = require('fs-extra');

async function exportContracts(contracts) {
  const contractsObj = JSON.parse(fs.readFileSync('./contracts.json'));
  for (const contract of contracts) {
    const contractObj = JSON.parse(fs.readFileSync(`./artifacts/contracts/${contract}`));
    contractsObj.contracts[contractObj.contractName] = {
      address: contractObj.address,
      abi: contractObj.abi,
      bytecode: contractObj.bytecode,
    };
  }
  fs.outputJsonSync('./contracts.json', contractsObj);
}

module.exports = {
  exportContracts,
};
