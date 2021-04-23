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
const ALCHEMY_KEY = process.env.ALCHEMY_KEY || '';

const { extendEnvironment, task, subtask, extendConfig } = require('hardhat/config');

const { utils } = require('ethers');
const fs = require('fs');

const { isAddress, getAddress, formatUnits, parseUnits } = utils;

const defaultNetwork = 'hardhat';

function mnemonic() {
  try {
    return fs.readFileSync('./mnemonic.txt').toString().trim();
  } catch (e) {}
  return '';
}

const CHAIN_IDS = {
  hardhat: 31337,
  kovan: 42,
  goerli: 5,
  mainnet: 1,
  rinkeby: 4,
  ropsten: 3,
  dockerParity: 17,
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
    rinkeby: {
      url: 'https://rinkeby.infura.io/v3/c954231486fa42ccb6d132b406483d14',
      accounts: {
        mnemonic: mnemonic(),
      },
      saveDeployments: true,
    },
    mainnet: {
      url: 'https://mainnet.infura.io/v3/c954231486fa42ccb6d132b406483d14',
      accounts: {
        mnemonic: mnemonic(),
      },
      gasPrice: 56000000000,
      saveDeployments: true,
    },
    xdai: {
      url: 'https://dai.poa.network',
      gasPrice: 1000000000,
      accounts: {
        mnemonic: mnemonic(),
      },
      saveDeployments: true,
    },
  },
  namedAccounts: {
    deployer: {
      default: 0,
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

const DEBUG = false;

function debug(text) {
  if (DEBUG) {
    console.log(text);
  }
}

require('./lib/tasks/node-ready');

task('generate', 'Create a mnemonic for builder deploys', async (_, { ethers }) => {
  const bip39 = require('bip39');
  const hdkey = require('ethereumjs-wallet/hdkey');
  const mnemonic = bip39.generateMnemonic();
  if (DEBUG) console.log('mnemonic', mnemonic);
  const seed = await bip39.mnemonicToSeed(mnemonic);
  if (DEBUG) console.log('seed', seed);
  const hdwallet = hdkey.fromMasterSeed(seed);
  const wallet_hdpath = "m/44'/60'/0'/0/";
  const account_index = 0;
  const fullPath = wallet_hdpath + account_index;
  if (DEBUG) console.log('fullPath', fullPath);
  const wallet = hdwallet.derivePath(fullPath).getWallet();
  const privateKey = '0x' + wallet._privKey.toString('hex');
  if (DEBUG) console.log('privateKey', privateKey);
  const EthUtil = require('ethereumjs-util');
  const address = '0x' + EthUtil.privateToAddress(wallet._privKey).toString('hex');
  console.log('🔐 Account Generated as ' + address + '.txt and saved as mnemonic.txt');
  console.log("💬 Use 'yarn run account' to get more information about the deployment account.");

  fs.writeFileSync('./mnemonic.txt', mnemonic.toString());
});

task('account', 'Get balance informations for the deployment account.', async (_, { ethers }) => {
  const hdkey = require('ethereumjs-wallet/hdkey');
  const bip39 = require('bip39');
  const mnemonic = fs.readFileSync('./mnemonic.txt').toString().trim();
  if (DEBUG) console.log('mnemonic', mnemonic);
  const seed = await bip39.mnemonicToSeed(mnemonic);
  if (DEBUG) console.log('seed', seed);
  const hdwallet = hdkey.fromMasterSeed(seed);
  const wallet_hdpath = "m/44'/60'/0'/0/";
  const account_index = 0;
  const fullPath = wallet_hdpath + account_index;
  if (DEBUG) console.log('fullPath', fullPath);
  const wallet = hdwallet.derivePath(fullPath).getWallet();
  const privateKey = '0x' + wallet._privKey.toString('hex');
  if (DEBUG) console.log('privateKey', privateKey);
  const EthUtil = require('ethereumjs-util');
  const address = '0x' + EthUtil.privateToAddress(wallet._privKey).toString('hex');

  const qrcode = require('qrcode-terminal');
  qrcode.generate(address);
  console.log('‍📬 Deployer Account is ' + address);
  for (const n in config.networks) {
    // console.log(config.networks[n],n)
    try {
      const provider = new ethers.providers.JsonRpcProvider(config.networks[n].url);
      const balance = await provider.getBalance(address);
      console.log(' -- ' + n + ' --  -- -- 📡 ');
      console.log('   balance: ' + ethers.utils.formatEther(balance));
      console.log('   nonce: ' + (await provider.getTransactionCount(address)));
    } catch (e) {
      if (DEBUG) {
        console.log(e);
      }
    }
  }
});

async function addr(ethers, addr) {
  if (isAddress(addr)) {
    return getAddress(addr);
  }
  const accounts = await ethers.provider.listAccounts();
  if (accounts[addr] !== undefined) {
    return accounts[addr];
  }
  throw `Could not normalize address: ${addr}`;
}

task('accounts', 'Prints the list of accounts', async (_, { ethers }) => {
  const accounts = await ethers.provider.listAccounts();
  accounts.forEach((account) => console.log(account));
});

task('blockNumber', 'Prints the block number', async (_, { ethers }) => {
  const blockNumber = await ethers.provider.getBlockNumber();
  console.log(blockNumber);
});

task('balance', "Prints an account's balance")
  .addPositionalParam('account', "The account's address")
  .setAction(async (taskArgs, { ethers }) => {
    const balance = await ethers.provider.getBalance(await addr(ethers, taskArgs.account));
    console.log(formatUnits(balance, 'ether'), 'ETH');
  });

function send(signer, txparams) {
  return signer.sendTransaction(txparams, (error, transactionHash) => {
    if (error) {
      debug(`Error: ${error}`);
    }
    debug(`transactionHash: ${transactionHash}`);
    // checkForReceipt(2, params, transactionHash, resolve)
  });
}

task('send', 'Send ETH')
  .addParam('from', 'From address or account index')
  .addOptionalParam('to', 'To address or account index')
  .addOptionalParam('amount', 'Amount to send in ether')
  .addOptionalParam('data', 'Data included in transaction')
  .addOptionalParam('gasPrice', 'Price you are willing to pay in gwei')
  .addOptionalParam('gasLimit', 'Limit of how much gas to spend')

  .setAction(async (taskArgs, { network, ethers }) => {
    const from = await addr(ethers, taskArgs.from);
    debug(`Normalized from address: ${from}`);
    const fromSigner = await ethers.provider.getSigner(from);

    let to;
    if (taskArgs.to) {
      to = await addr(ethers, taskArgs.to);
      debug(`Normalized to address: ${to}`);
    }

    const txRequest = {
      from: await fromSigner.getAddress(),
      to,
      value: parseUnits(taskArgs.amount ? taskArgs.amount : '0', 'ether').toHexString(),
      nonce: await fromSigner.getTransactionCount(),
      gasPrice: parseUnits(taskArgs.gasPrice ? taskArgs.gasPrice : '1.001', 'gwei').toHexString(),
      gasLimit: taskArgs.gasLimit ? taskArgs.gasLimit : 24000,
      chainId: network.config.chainId,
    };

    if (taskArgs.data !== undefined) {
      txRequest.data = taskArgs.data;
      debug(`Adding data to payload: ${txRequest.data}`);
    }
    debug(txRequest.gasPrice / 1000000000 + ' gwei');
    debug(JSON.stringify(txRequest, null, 2));

    return send(fromSigner, txRequest);
  });
