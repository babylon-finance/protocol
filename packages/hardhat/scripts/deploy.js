const { ethers } = require("hardhat");
const fs = require("fs");
const chalk = require("chalk");
const argsUtil = require("../utils/arguments.js");
const { deployFolioFixture } = require("../test/fixtures/ControllerFixture");
const addresses = require("../utils/addresses");

async function deploy(name, _args) {
  const args = _args || [];

  console.log(`📄 ${name}`);
  const contractArtifacts = await ethers.getContractFactory(name);
  const contract = await contractArtifacts.deploy(...args);
  console.log(
    chalk.cyan(name),
    "deployed to:",
    chalk.magenta(contract.address)
  );
  fs.writeFileSync(`artifacts/${name}.address`, contract.address);
  console.log("\n");
  return contract;
}

const isSolidity = fileName =>
  fileName.indexOf(".sol") >= 0 && fileName.indexOf(".swp.") < 0;

async function autoDeploy() {
  const contractList = fs.readdirSync(config.paths.sources);
  return contractList
    .filter(fileName => isSolidity(fileName))
    .reduce((lastDeployment, fileName) => {
      const contractName = fileName.replace(".sol", "");
      const args = arguments.readArgumentsFile(contractName);

      // Wait for last deployment to complete before starting the next
      return lastDeployment.then(resultArrSoFar =>
        deploy(contractName, args).then(result => [...resultArrSoFar, result])
      );
    }, Promise.resolve([]));
}

async function main() {
  deployFolioFixture();
  console.log("📡 Deploy complete! \n");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
