require('@nomiclabs/hardhat-ethers');

const fs = require('fs-extra');

const chalk = require('chalk');

const exportDir = './export/contracts';

fs.ensureDirSync(exportDir);

const isSolidity = (fileName) => fileName.indexOf('.sol') >= 0 && fileName.indexOf('.swp') < 0;

function buildAddress(contractName, address) {
  fs.writeFileSync(`${exportDir}/${contractName}.address.js`, `module.exports = "${address}";`);
}

function exportContract(contractName, path) {
  console.log('Exporting', chalk.cyan(contractName), 'to', chalk.yellow(exportDir));
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
      `${exportDir}/${contractName}.abi.js`,
      `module.exports = ${JSON.stringify(contract.abi, null, 2)};`,
    );
    fs.writeFileSync(`${exportDir}/${contractName}.bytecode.js`, `module.exports = "${contract.bytecode}";`);
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
  const exportAndPushContract = (file, path = '') => {
    if (file.indexOf('.sol') >= 0) {
      const contractName = file.replace('.sol', '');
      // Add contract to list if exporting is successful
      if (exportContract(contractName, path)) {
        finalContractList.push(contractName);
      }
    }
  };

  if (!fs.existsSync(exportDir)) {
    fs.mkdirSync(exportDir);
  }

  // Internal Integrations
  const lend = ['AaveLendIntegration.sol', 'CompoundLendIntegration.sol'];
  const passive = ['YearnVaultIntegration.sol'];
  const pool = [
    'BalancerIntegration.sol',
    'UniswapPoolIntegration.sol',
    'OneInchPoolIntegration.sol',
    'SushiswapPoolIntegration.sol',
  ];
  const trade = ['OneInchTradeIntegration.sol', 'KyberTradeIntegration.sol'];

  lend.forEach((file) => {
    exportAndPushContract(file, 'integrations/lend/');
  });

  passive.forEach((file) => {
    exportAndPushContract(file, 'integrations/passive/');
  });

  pool.forEach((file) => {
    exportAndPushContract(file, 'integrations/pool/');
  });

  trade.forEach((file) => {
    exportAndPushContract(file, 'integrations/trade/');
  });

  // Garden Contracts
  const garden = ['GardenFactory.sol', 'Garden.sol'];
  garden.forEach((file) => {
    exportAndPushContract(file, 'gardens/');
  });

  // Strategy Factory Contracts
  const strategies = ['LongStrategyFactory.sol', 'LiquidityPoolStrategyFactory.sol', 'Strategy.sol'];
  strategies.forEach((file) => {
    exportAndPushContract(file, 'strategies/');
  });

  // Internal Interfaces
  const interfaces = ['IBabController.sol', 'IGarden.sol', 'IGardenValuer.sol', 'IIntegration.sol', 'IStrategy.sol'];

  interfaces.forEach((file) => {
    exportAndPushContract(file, 'interfaces/');
  });

  const contractList = fs.readdirSync(config.paths.sources).filter((fileName) => isSolidity(fileName));

  contractList.forEach((file) => {
    exportAndPushContract(file);
  });

  // External interfaces
  const externalInterfaces = [
    { name: 'IKyberNetworkProxy.sol', path: 'interfaces/external/kyber/' },
    { name: 'IVault.sol', path: 'interfaces/external/yearn/' },
    { name: 'IERC20.sol', path: '../@openzeppelin/contracts/token/ERC20/' },
    { name: 'YRegistry.sol', path: 'interfaces/external/yearn/' },
  ];

  externalInterfaces.forEach((interfaceC) => {
    exportAndPushContract(interfaceC.name, interfaceC.path);
  });

  // Export addresses
  fs.copyFileSync('utils/addresses.js', `${exportDir}/addresses.js`);
  fs.copyFileSync('utils/constants.js', `${exportDir}/constants.js`);
  fs.writeFileSync(`${exportDir}/contracts.js`, `module.exports = ${JSON.stringify(finalContractList)};`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
