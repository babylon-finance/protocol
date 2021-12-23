require('dotenv/config');
const { task } = require('hardhat/config');
const { AdminClient } = require('defender-admin-client');

const API_KEY = process.env.DEFENDER_API_KEY;
const API_SECRET = process.env.DEFENDER_API_SECRET;
const MULTI_SEND = '0x8D29bE29923b68abfDD21e541b9374737B49cdAD';
const MULTI_SIG_FOUNDATION = '0x97FcC2Ae862D03143b393e9fA73A32b563d57A6e';

const GARDEN_BEACON = '0xc8f44C560efe396a6e57e48fF07205bD28AF5E75';
const STRATEGY_BEACON = '0x31946680978CEFB010e5f5Fa8b8134c058cba7dC';
const PROXY_ADMIN = '0x0C085fd8bbFD78db0107bF17047E8fa906D871DC';

const CONTROLLER_PROXY = '0xD4a5b5fcB561dAF3aDF86F8477555B92FBa43b5F';
const DISTRIBUTOR_PROXY = '0x40154ad8014Df019a53440A60eD351dfbA47574e';

/// Encodes the transaction as packed bytes of:
/// - `operation` as a `uint8` with `0` for a `call` or `1` for a `delegatecall` (=> 1 byte),
/// - `to` as an `address` (=> 20 bytes),
/// - `value` as a `uint256` (=> 32 bytes),
/// -  length of `data` as a `uint256` (=> 32 bytes),
/// - `data` as `bytes`.
const encodeMetaTransaction = (tx) => {
  const data = ethers.utils.arrayify(tx.data);
  const encoded = ethers.utils.solidityPack(
    ['uint8', 'address', 'uint256', 'uint256', 'bytes'],
    [tx.operation, tx.to, tx.value, data.length, data],
  );
  return encoded.slice(2);
};

export const encodeMultiSend = (txs) => {
  return '0x' + txs.map((tx) => encodeMetaTransaction(tx)).join('');
};

// npx hardhat upgrade-multisig --network mainnet --controller BabControllerV11 --distributor RewardsDistributorV11 --strategy StrategyV14 --garden GardenV15
task('upgrade-multisig')
  .addOptionalParam('controller')
  .addOptionalParam('distributor')
  .addOptionalParam('garden')
  .addOptionalParam('strategy')
  .addFlag('calldata')
  .setAction(
    async (
      args,
      { network, tenderly, getTenderlyContract, upgradesDeployer, getContract, ethers, getGasPrice, deployments },
      runSuper,
    ) => {
      const { controller, distributor, garden, strategy, calldata } = args;

      const multiSendTxData = encodeMultiSend(
        [
          !!controller
            ? {
                // upgrade BabController
                operation: 0, // call
                to: PROXY_ADMIN,
                value: '0',
                data: new ethers.utils.Interface([
                  'function upgrade(address proxy, address implementation)',
                ]).encodeFunctionData('upgrade', [CONTROLLER_PROXY, (await deployments.get(controller)).address]),
              }
            : undefined,
          !!distributor
            ? {
                // upgrade RewardsDistributor
                operation: 0, // call
                to: PROXY_ADMIN,
                value: '0',
                data: new ethers.utils.Interface([
                  'function upgrade(address proxy, address implementation)',
                ]).encodeFunctionData('upgrade', [DISTRIBUTOR_PROXY, (await deployments.get(distributor)).address]),
              }
            : undefined,
          !!garden
            ? {
                // upgrade Garden
                operation: 0, // call
                to: GARDEN_BEACON,
                value: '0',
                data: new ethers.utils.Interface([
                  'function upgradeTo(address implementation)',
                ]).encodeFunctionData('upgradeTo', [(await deployments.get(garden)).address]),
              }
            : undefined,
          !!strategy
            ? {
                // upgrade Strategy
                operation: 0, // call
                to: STRATEGY_BEACON,
                value: '0',
                data: new ethers.utils.Interface([
                  'function upgradeTo(address implementation)',
                ]).encodeFunctionData('upgradeTo', [(await deployments.get(strategy)).address]),
              }
            : undefined,
        ].filter((o) => !!o),
      );
      console.log(`Data for MultiSend ${multiSendTxData}`);

      if (calldata) {
        return;
      }

      const client = new AdminClient({ apiKey: API_KEY, apiSecret: API_SECRET });
      await client.createProposal({
        contract: { address: MULTI_SEND, network: 'mainnet' }, // Gnosis Multi Send
        title: 'Upgrade Babylon Proxies',
        description: 'Upgrades BabController, RewardsDistributor, Garden and Strategy proxies',
        type: 'custom',
        functionInterface: { name: 'multiSend', inputs: [{ type: 'bytes', name: 'transactions' }] },
        functionInputs: [multiSendTxData],
        via: MULTI_SIG_FOUNDATION, // Multisig address
        viaType: 'Gnosis Safe',
        metadata: { operationType: 'delegateCall' }, // Issue a delegatecall instead of a regular call
      });

      console.log('Done ✅');
    },
  );
