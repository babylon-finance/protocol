require("@nomiclabs/hardhat-ethers");

const fs = require("fs");
const chalk = require("chalk");

const publishDir = "../react-app/src/contracts";

function publishContract(contractName) {
  console.log(
    "Publishing",
    chalk.cyan(contractName),
    "to",
    chalk.yellow(publishDir)
  );
  try {
    const contractFile = fs
      .readFileSync(`${config.paths.artifacts}/contracts/${contractName}.sol/${contractName}.json`)
      .toString();
    let address;
    try {
      address = fs
        .readFileSync(`${config.paths.artifacts}/${contractName}.address`)
        .toString();
    } catch (err) {
      address = null;
    }
    const contract = JSON.parse(contractFile);
    fs.writeFileSync(
      `${publishDir}/${contractName}.abi.js`,
      `module.exports = ${JSON.stringify(contract.abi, null, 2)};`
    );
    fs.writeFileSync(
      `${publishDir}/${contractName}.bytecode.js`,
      `module.exports = "${contract.bytecode}";`
    );
    if (address) {
      buildAddress(publishDir, contractName, address);
    }
    return true;
  } catch (e) {
    console.log(e);
    return false;
  }
}

function buildAddress(publishDir, contractName, address) {
  fs.writeFileSync(
    `${publishDir}/${contractName}.address.js`,
    `module.exports = "${address}";`
  );
}

async function main() {
  if (!fs.existsSync(publishDir)) {
    fs.mkdirSync(publishDir);
  }
  const finalContractList = [];
  fs.readdirSync(config.paths.sources).forEach((file) => {
    if (file.indexOf(".sol") >= 0) {
      const contractName = file.replace(".sol", "");
      // Add contract to list if publishing is successful
      if (publishContract(contractName)) {
        finalContractList.push(contractName);
      }
    }
  });
  fs.writeFileSync(
    `${publishDir}/contracts.js`,
    `module.exports = ${JSON.stringify(finalContractList)};`
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
