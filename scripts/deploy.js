const { ethers } = require('hardhat');
const fs = require('fs');
const chalk = require('chalk');
const {
  createStrategy,
  executeStrategy,
  finalizeStrategy,
  injectFakeProfits,
} = require('../test/fixtures/StrategyHelper');
const { deployFolioFixture } = require('../test/fixtures/ControllerFixture');
const { ONE_DAY_IN_SECONDS } = require('../utils/constants');

async function deploy(name, _args) {
  const args = _args || [];

  console.log(`📄 ${name}`);
  const contractArtifacts = await ethers.getContractFactory(name);
  const contract = await contractArtifacts.deploy(...args);
  console.log(chalk.cyan(name), 'deployed to:', chalk.magenta(contract.address));
  fs.writeFileSync(`artifacts/${name}.address`, contract.address);
  console.log('\n');
  return contract;
}

const isSolidity = (fileName) => fileName.indexOf('.sol') >= 0 && fileName.indexOf('.swp.') < 0;

async function autoDeploy() {
  const contractList = fs.readdirSync(config.paths.sources);
  return contractList
    .filter((fileName) => isSolidity(fileName))
    .reduce((lastDeployment, fileName) => {
      const contractName = fileName.replace('.sol', '');
      const args = arguments.readArgumentsFile(contractName);

      // Wait for last deployment to complete before starting the next
      return lastDeployment.then((resultArrSoFar) =>
        deploy(contractName, args).then((result) => [...resultArrSoFar, result]),
      );
    }, Promise.resolve([]));
}

async function main() {
  const { contractsToPublish, garden3, signer1, signer2, signer3, kyberTradeIntegration } = await deployFolioFixture();
  console.log('Contracts deployed...');

  console.log('Deploying test strategies...');
  await createStrategy('long', 'active', [signer1, signer2, signer3], kyberTradeIntegration.address, garden3);
  await createStrategy('long', 'active', [signer1, signer2, signer3], kyberTradeIntegration.address, garden3);
  console.log('Active strategies deployed...');
  console.log('Deploying finalized strategy with profits...');
  const strategy1 = await createStrategy(
    'long',
    'vote',
    [signer1, signer2, signer3],
    kyberTradeIntegration.address,
    garden3,
  );
  await executeStrategy(strategy1);
  await injectFakeProfits(strategy1, ethers.utils.parseEther('5000'));
  await finalizeStrategy(strategy1, { time: ONE_DAY_IN_SECONDS * 30 });
  console.log('Test strategies deployed...');

  console.log('Syncing artifacts for export...');
  // Let the fixture response determine which contracts to write address
  // files for and export accordingly in contracts.js.
  contractsToPublish.forEach((contractObj) => {
    const name = contractObj.name;
    const address = contractObj.contract.address;

    if (!name) {
      console.log('No name provided for contract, exiting...');
      process.exit(1);
    }

    fs.writeFileSync(`artifacts/${name}.address`, address);
  });

  console.log('Artifacts sync complete..');
  console.log('📡 Contract deploy complete! \n');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
