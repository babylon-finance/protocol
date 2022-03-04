require('dotenv/config');
require('@babel/register');
require('@nomiclabs/hardhat-ethers');
require('@openzeppelin/hardhat-upgrades');
require('@nomiclabs/hardhat-waffle');
require('@nomiclabs/hardhat-etherscan');

require('hardhat-deploy');
require('hardhat-contract-sizer');
require('hardhat-docgen');
require('hardhat-gas-reporter');
require('hardhat-log-remover');
require('hardhat-watcher');
require('hardhat-spdx-license-identifier');

require('@tenderly/hardhat-tenderly');
require('solidity-coverage');

require('./lib/plugins/upgrades');
require('./lib/plugins/gasnow');
require('./lib/plugins/utils');

require('./lib/tasks/node-ready');
require('./lib/tasks/export');
require('./lib/tasks/export-token-list');
require('./lib/tasks/gate');
require('./lib/tasks/increase-time');
require('./lib/tasks/upgrade-admin');
require('./lib/tasks/upgrade-beacon');
require('./lib/tasks/upgrade-multisig');
require('./lib/tasks/deploy-contract');
require('./lib/tasks/tvl');
require('./lib/tasks/vesting');
require('./lib/tasks/users');
require('./lib/tasks/gardens');
require('./lib/tasks/stuck');
require('./lib/tasks/mining');
require('./lib/tasks/strategy-expire');
require('./lib/tasks/diff');

const OPTIMIZER = !(process.env.OPTIMIZER === 'false');
const COVERAGE = !!process.env.COVERAGE;

const FORK = !!process.env.FORK;

const ALCHEMY_KEY = process.env.ALCHEMY_KEY || '';
const DEPLOYER_PRIVATE_KEY =
  process.env.DEPLOYER_PRIVATE_KEY || '0000000000000000000000000000000000000000000000000000000000000000';

const OWNER_PRIVATE_KEY =
  process.env.OWNER_PRIVATE_KEY || '0000000000000000000000000000000000000000000000000000000000000000';

const defaultNetwork = 'hardhat';
const BLOCK_NUMBER = process.env.BLOCK_NUMBER || 14303000;

const CHAIN_IDS = {
  hardhat: 1337,
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
      forking: FORK
        ? {
            url: `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_KEY}`,
            blockNumber: +BLOCK_NUMBER,
          }
        : undefined,
      saveDeployments: true,
      gas: 9e6,
      initialBaseFeePerGas: 0,
    },
    mainnet: {
      chainId: CHAIN_IDS.mainnet,
      url: `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [`0x${DEPLOYER_PRIVATE_KEY}`, `0x${OWNER_PRIVATE_KEY}`],
      saveDeployments: true,
    },
    rinkeby: {
      chainId: CHAIN_IDS.rinkeby,
      url: `https://eth-rinkeby.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [`0x${DEPLOYER_PRIVATE_KEY}`, `0x${OWNER_PRIVATE_KEY}`],
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
    owner: {
      default: 1,
      [CHAIN_IDS.mainnet]: 1,
      [CHAIN_IDS.kovan]: 1,
      [CHAIN_IDS.ropsten]: 1,
      [CHAIN_IDS.goerli]: 1,
      [CHAIN_IDS.rinkeby]: 1,
    },
  },
  solidity: {
    compilers: [
      {
        version: '0.7.6',
        settings: {
          optimizer: {
            enabled: OPTIMIZER && !COVERAGE,
            runs: 999,
            details: COVERAGE
              ? {
                  yul: true,
                  yulDetails: {
                    stackAllocation: true,
                  },
                }
              : undefined,
          },
        },
      },
      {
        version: '0.8.2',
        settings: {
          optimizer: {
            enabled: OPTIMIZER && !COVERAGE,
            runs: 999,
            details: COVERAGE
              ? {
                  yul: true,
                  yulDetails: {
                    stackAllocation: true,
                  },
                }
              : undefined,
          },
        },
      },
    ],
    overrides: {
      '@uniswap/v3-core/contracts/libraries/FullMath.sol': {
        version: '0.7.6',
        settings: {},
      },
      '@uniswap/v3-core/contracts/libraries/TickMath.sol': {
        version: '0.7.6',
        settings: {},
      },
      '@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol': {
        version: '0.7.6',
        settings: {},
      },
    },
  },
  etherscan: {
    apiKey: 'JA61NTCWBMPN56AT7TFQ3IMPHH2M2NHSJJ',
  },
  tenderly: {
    username: 'babylon_finance',
    project: 'babylon',
  },
  paths: {
    tests: './test/unit',
    sources: './contracts',
    integrations: './contracts/integrations',
    artifacts: './artifacts',
    deploy: 'deployments/migrations',
    deployments: 'deployments/artifacts',
  },
  mocha: {
    timeout: 9999999,
  },

  watcher: {
    test: {
      tasks: [{ command: 'test', params: { testFiles: ['{path}'] } }],
      files: ['./test/**/*'],
      verbose: true,
    },
  },
};
