require('@nomiclabs/hardhat-ethers');

const fs = require('fs-extra');

const chalk = require('chalk');

const publishDir = './publish/contracts';

fs.ensureDirSync(publishDir);

const isSolidity = (fileName) => fileName.indexOf('.sol') >= 0 && fileName.indexOf('.swp') < 0;

function buildAddress(contractName, address) {
  fs.writeFileSync(`${publishDir}/${contractName}.address.js`, `module.exports = "${address}";`);
}

function publishContract(contractName, path) {
  console.log('Publishing', chalk.cyan(contractName), 'to', chalk.yellow(publishDir));
  try {
    const contractFile = fs
      .readFileSync(`${config.paths.artifacts}/contracts/${path}${contractName}.sol/${contractName}.json`)
      .toString();
    let address;
    try {
      address = fs.readFileSync(`${config.paths.artifacts}/${contractName}.address`).toString();
    } catch (err) {
      console.log(`No address file found for: ${contractName}, skipping address sync`);
      address = null;
    }
    const contract = JSON.parse(contractFile);
    fs.writeFileSync(
      `${publishDir}/${contractName}.abi.js`,
      `module.exports = ${JSON.stringify(contract.abi, null, 2)};`,
    );
    fs.writeFileSync(`${publishDir}/${contractName}.bytecode.js`, `module.exports = "${contract.bytecode}";`);
    if (address) {
      buildAddress(contractName, address);
      return true;
    }
    return false;
  } catch (e) {
    console.log(e);
    return false;
  }
}

async function main() {
  const finalContractList = [];
  const publishAndPushContract = (file, path = '') => {
    if (file.indexOf('.sol') >= 0) {
      const contractName = file.replace('.sol', '');
      // Add contract to list if publishing is successful
      if (publishContract(contractName, path)) {
        finalContractList.push(contractName);
      }
    }
  };

  if (!fs.existsSync(publishDir)) {
    fs.mkdirSync(publishDir);
  }

  // Internal Integrations
  const integrations = [
    'BalancerIntegration.sol',
    'YearnVaultIntegration.sol',
    'KyberTradeIntegration.sol',
    'UniswapPoolIntegration.sol',
  ];
  integrations.forEach((file) => {
    publishAndPushContract(file, 'integrations/');
  });
  // Factory Contracts
  const factories = ['LongStrategyFactory.sol', 'LiquidityPoolStrategyFactory', 'GardenFactory.sol'];
  factories.forEach((file) => {
    publishAndPushContract(file, 'gardens/');
  });
  // Internal Interfaces
  const interfaces = ['IGarden.sol', 'IRollingGarden.sol', 'IIntegration.sol', 'IStrategy.sol'];

  interfaces.forEach((file) => {
    publishAndPushContract(file, 'interfaces/');
  });

  const contractList = fs.readdirSync(config.paths.sources).filter((fileName) => isSolidity(fileName));

  contractList.forEach((file) => {
    publishAndPushContract(file);
  });

  // External interfaces
  const externalInterfaces = [
    { name: 'IKyberNetworkProxy.sol', path: 'interfaces/external/kyber/' },
    { name: 'IVault.sol', path: 'interfaces/external/yearn/' },
    { name: 'IERC20.sol', path: '../@openzeppelin/contracts/token/ERC20/' },
    { name: 'YRegistry.sol', path: 'interfaces/external/yearn/' },
  ];

  externalInterfaces.forEach((interfaceC) => {
    publishAndPushContract(interfaceC.name, interfaceC.path);
  });
  // Publish addresses
  fs.copyFileSync('utils/addresses.js', `${publishDir}/addresses.js`);
  fs.copyFileSync('utils/constants.js', `${publishDir}/constants.js`);
  fs.writeFileSync(`${publishDir}/contracts.js`, `module.exports = ${JSON.stringify(finalContractList)};`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
