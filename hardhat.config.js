require('dotenv/config');
require('@nomiclabs/hardhat-ethers');
require('@openzeppelin/hardhat-upgrades');
require('@nomiclabs/hardhat-waffle');
require('hardhat-deploy');
require('hardhat-contract-sizer');
require('hardhat-docgen');
require('hardhat-gas-reporter');
require('solidity-coverage');
require('@typechain/hardhat');

require('./lib/plugins/upgrades');

require('./lib/tasks/node-ready');

const ALCHEMY_KEY = process.env.ALCHEMY_KEY || '';
const DEPLOYER_PRIVATE_KEY =
  process.env.DEPLOYER_PRIVATE_KEY || '0000000000000000000000000000000000000000000000000000000000000000';

const defaultNetwork = 'hardhat';

const CHAIN_IDS = {
  hardhat: 31337,
  kovan: 42,
  goerli: 5,
  mainnet: 1,
  rinkeby: 4,
  ropsten: 3,
};

module.exports = {
  defaultNetwork,

  gasReporter: {
    currency: 'USD',
    coinmarketcap: 'f903b99d-e117-4e55-a7a8-ff5dd8ad5bed',
    enabled: !!process.env.REPORT_GAS,
  },

  networks: {
    hardhat: {
      chainId: CHAIN_IDS.hardhat,
      blockGasLimit: 0x1fffffffffffff,
      allowUnlimitedContractSize: true,
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_KEY}`,
        blockNumber: 12160000,
      },
      saveDeployments: true,
    },
    mainnet: {
      chainId: CHAIN_IDS.mainnet,
      url: `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [`0x${DEPLOYER_PRIVATE_KEY}`],
      saveDeployments: true,
    },
    rinkeby: {
      chainId: CHAIN_IDS.rinkeby,
      url: `https://eth-rinkeby.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [`0x${DEPLOYER_PRIVATE_KEY}`],
      saveDeployments: true,
    },
  },
  namedAccounts: {
    deployer: {
      default: 0,
      [CHAIN_IDS.mainnet]: 0,
      [CHAIN_IDS.kovan]: 0,
      [CHAIN_IDS.ropsten]: 0,
      [CHAIN_IDS.goerli]: 0,
      [CHAIN_IDS.rinkeby]: 0,
    },
  },
  solidity: {
    compilers: [
      {
        version: '0.7.6',
        settings: {
          optimizer: {
            enabled: true,
            runs: 999,
          },
        },
      },
    ],
  },
  paths: {
    sources: './contracts',
    integrations: './contracts/integrations',
    artifacts: './artifacts',
  },
  mocha: {
    timeout: 120000,
  },
};
