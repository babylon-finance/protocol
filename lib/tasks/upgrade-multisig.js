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
const VTABLE_BEACON = '0xaAaCb63Ab80969af93b811DEB81dDEB4C8710591';

const CONTROLLER_PROXY = '0xD4a5b5fcB561dAF3aDF86F8477555B92FBa43b5F';
const DISTRIBUTOR_PROXY = '0x40154ad8014Df019a53440A60eD351dfbA47574e';
const ASSISTANT_PROXY = '0x90F3923427768d6dC7970417B0F413B7DD059011';
const HEART_PROXY = '0x51e6775b7bE2eA1d20cA02cFEeB04453366e72C8';

const MASTER_SWAPPER = '0xa8C60f2e551BcA1a321C3D2776063202FF4Bc79C';

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

// npx hardhat upgrade-multisig --network mainnet --assistant AssistantV2 --controller BabControllerV11 --distributor RewardsDistributorV11 --strategy StrategyV14 --garden GardenV15
task('upgrade-multisig')
  .addOptionalParam('controller')
  .addOptionalParam('distributor')
  .addOptionalParam('garden')
  .addOptionalParam('adminGarden')
  .addOptionalParam('strategyGarden')
  .addOptionalParam('strategy')
  .addOptionalParam('heart')
  .addOptionalParam('assistant')
  .addOptionalParam('swapper')
  .addOptionalParam('curve')
  .addOptionalParam('oracle')
  .addOptionalParam('buy')
  .addOptionalParam('liquidity')
  .addOptionalParam('deposit')
  .addOptionalParam('lend')
  .addOptionalParam('tradeCurve')
  .addOptionalParam('tradeUniV3')
  .addOptionalParam('tradeSynth')
  .addOptionalParam('tradeUniV2')
  .addFlag('calldata')
  .setAction(
    async (
      args,
      { network, tenderly, getTenderlyContract, upgradesDeployer, getContract, ethers, getGasPrice, deployments },
      runSuper,
    ) => {
      const {
        controller,
        distributor,
        garden,
        adminGarden,
        strategyGarden,
        strategy,
        assistant,
        heart,
        swapper,
        curve,
        oracle,
        buy,
        liquidity,
        deposit,
        lend,
        borrow,
        tradeCurve,
        tradeUniV3,
        tradeSynth,
        tradeUniV2,
        calldata,
      } = args;

      const adminGardenModule = !!adminGarden ? await deployments.get(adminGarden) : undefined;
      const adminGardenModuleContract = !!adminGarden
        ? await ethers.getContractAt(adminGarden, adminGardenModule.address)
        : undefined;
      const strategyGardenModule = !!strategyGarden ? await deployments.get(strategyGarden) : undefined;
      const strategyGardenModuleContract = !!strategyGarden
        ? await ethers.getContractAt(strategyGarden, strategyGardenModule.address)
        : undefined;

      const multiSendTxData = encodeMultiSend(
        [
          !!controller
            ? {
                // BabController
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
                // RewardsDistributor
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
                // Garden
                operation: 0, // call
                to: GARDEN_BEACON,
                value: '0',
                data: new ethers.utils.Interface([
                  'function upgradeTo(address implementation)',
                ]).encodeFunctionData('upgradeTo', [(await deployments.get(garden)).address]),
              }
            : undefined,
          !!adminGarden
            ? {
                // AdminGardenModule
                operation: 0, // call
                to: VTABLE_BEACON,
                value: '0',
                data: new ethers.utils.Interface([
                  'function updateVTable(tuple(address implementation, bytes4[] selectors)[] modules)',
                ]).encodeFunctionData('updateVTable', [
                  [
                    [
                      adminGardenModule.address,
                      Object.keys(adminGardenModuleContract.interface.functions).map((func) =>
                        adminGardenModuleContract.interface.getSighash(func),
                      ),
                    ],
                  ],
                ]),
              }
            : undefined,
          !!strategyGarden
            ? {
                // StrategyGardenModule
                operation: 0, // call
                to: VTABLE_BEACON,
                value: '0',
                data: new ethers.utils.Interface([
                  'function updateVTable(tuple(address implementation, bytes4[] selectors)[] modules)',
                ]).encodeFunctionData('updateVTable', [
                  [
                    [
                      strategyGardenModule.address,
                      Object.keys(strategyGardenModuleContract.interface.functions).map((func) =>
                        strategyGardenModuleContract.interface.getSighash(func),
                      ),
                    ],
                  ],
                ]),
              }
            : undefined,
          !!strategy
            ? {
                // Strategy
                operation: 0, // call
                to: STRATEGY_BEACON,
                value: '0',
                data: new ethers.utils.Interface([
                  'function upgradeTo(address implementation)',
                ]).encodeFunctionData('upgradeTo', [(await deployments.get(strategy)).address]),
              }
            : undefined,
          !!heart
            ? {
                // HEART
                operation: 0, // call
                to: PROXY_ADMIN,
                value: '0',
                data: new ethers.utils.Interface([
                  'function upgrade(address proxy, address implementation)',
                ]).encodeFunctionData('upgrade', [HEART_PROXY, (await deployments.get(heart)).address]),
              }
            : undefined,
          !!assistant
            ? {
                // Assistant
                operation: 0, // call
                to: PROXY_ADMIN,
                value: '0',
                data: new ethers.utils.Interface([
                  'function upgrade(address proxy, address implementation)',
                ]).encodeFunctionData('upgrade', [ASSISTANT_PROXY, (await deployments.get(assistant)).address]),
              }
            : undefined,
          !!swapper
            ? {
                // MasterSwapper
                operation: 0, // call
                to: CONTROLLER_PROXY,
                value: '0',
                data: new ethers.utils.Interface([
                  'function setMasterSwapper(address _newDefaultMasterSwapper)',
                ]).encodeFunctionData('setMasterSwapper', [(await deployments.get(swapper)).address]),
              }
            : undefined,
          !!borrow
            ? {
                // Borrow Operation
                operation: 0, // call
                to: CONTROLLER_PROXY,
                value: '0',
                data: new ethers.utils.Interface([
                  'function setOperation(uint8 _kind, address _operation)',
                ]).encodeFunctionData('setOperation', [4, (await deployments.get(borrow)).address]),
              }
            : undefined,
          !!lend
            ? {
                // Lend Operation
                operation: 0, // call
                to: CONTROLLER_PROXY,
                value: '0',
                data: new ethers.utils.Interface([
                  'function setOperation(uint8 _kind, address _operation)',
                ]).encodeFunctionData('setOperation', [3, (await deployments.get(lend)).address]),
              }
            : undefined,
          !!deposit
            ? {
                // Deposit Operation
                operation: 0, // call
                to: CONTROLLER_PROXY,
                value: '0',
                data: new ethers.utils.Interface([
                  'function setOperation(uint8 _kind, address _operation)',
                ]).encodeFunctionData('setOperation', [2, (await deployments.get(deposit)).address]),
              }
            : undefined,
          !!liquidity
            ? {
                // Liquidity Operation
                operation: 0, // call
                to: CONTROLLER_PROXY,
                value: '0',
                data: new ethers.utils.Interface([
                  'function setOperation(uint8 _kind, address _operation)',
                ]).encodeFunctionData('setOperation', [1, (await deployments.get(liquidity)).address]),
              }
            : undefined,
          !!buy
            ? {
                // Buy Operation
                operation: 0, // call
                to: CONTROLLER_PROXY,
                value: '0',
                data: new ethers.utils.Interface([
                  'function setOperation(uint8 _kind, address _operation)',
                ]).encodeFunctionData('setOperation', [0, (await deployments.get(buy)).address]),
              }
            : undefined,
          !!oracle
            ? {
                // PriceOracle
                operation: 0, // call
                to: CONTROLLER_PROXY,
                value: '0',
                data: new ethers.utils.Interface([
                  'function editPriceOracle(address _priceOracle)',
                ]).encodeFunctionData('editPriceOracle', [(await deployments.get(oracle)).address]),
              }
            : undefined,
          !!curve
            ? {
                // CurveMetaRegistry
                operation: 0, // call
                to: CONTROLLER_PROXY,
                value: '0',
                data: new ethers.utils.Interface([
                  'function editCurveMetaRegistry(address _curveMetaRegistry)',
                ]).encodeFunctionData('editCurveMetaRegistry', [(await deployments.get(curve)).address]),
              }
            : undefined,
          !!tradeUniV2
            ? {
                // UniV2 Trade
                operation: 0, // call
                to: MASTER_SWAPPER,
                value: '0',
                data: new ethers.utils.Interface([
                  'function updateTradeAddress(uint256 _index, address _newAddress)',
                ]).encodeFunctionData('updateTradeAddress', [3, (await deployments.get(tradeUniV2)).address]),
              }
            : undefined,
          !!tradeSynth
            ? {
                // Synthetix Trade
                operation: 0, // call
                to: MASTER_SWAPPER,
                value: '0',
                data: new ethers.utils.Interface([
                  'function updateTradeAddress(uint256 _index, address _newAddress)',
                ]).encodeFunctionData('updateTradeAddress', [2, (await deployments.get(tradeSynth)).address]),
              }
            : undefined,
          !!tradeUniV3
            ? {
                // UniV3 Trade
                operation: 0, // call
                to: MASTER_SWAPPER,
                value: '0',
                data: new ethers.utils.Interface([
                  'function updateTradeAddress(uint256 _index, address _newAddress)',
                ]).encodeFunctionData('updateTradeAddress', [1, (await deployments.get(tradeUniV3)).address]),
              }
            : undefined,
          !!tradeCurve
            ? {
                // Curve Trade
                operation: 0, // call
                to: MASTER_SWAPPER,
                value: '0',
                data: new ethers.utils.Interface([
                  'function updateTradeAddress(uint256 _index, address _newAddress)',
                ]).encodeFunctionData('updateTradeAddress', [0, (await deployments.get(tradeCurve)).address]),
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
        title: 'Upgrade Babylon Protocol',
        description: `Upgrades
        ${!!controller ? 'BabController,' : ''}
        ${!!assistant ? 'Assistant,' : ''}
        ${!!distributor ? 'RewardsDistributor,' : ''}
        ${!!garden ? 'Garden,' : ''}
        ${!!strategy ? 'Strategy,' : ''}
        ${!!garden ? 'Garden,' : ''}
        ${!!lend ? 'LendOperation,' : ''}
        ${!!borrow ? 'BorrowOperation,' : ''}
        ${!!deposit ? 'DepositOperation,' : ''}
        ${!!buy ? 'BuyOperation,' : ''}
        ${!!liquidity ? 'LiquidityOperation,' : ''}
        ${!!curve ? 'CurveMetaRegistry,,' : ''}
        ${!!tradeCurve ? 'TradeCurve,' : ''}
        ${!!tradeUniV3 ? 'TradeUniV3,' : ''}
        ${!!tradeSynth ? 'TradeSynth,' : ''}
        ${!!tradeUniV2 ? 'TradeUniV2,' : ''}
        ${!!adminGarden ? 'adminGarden,' : ''}
        ${!!strategyGarden ? 'strategyGarden,' : ''}
        ${!!oracle ? 'PriceOracle' : ''}`,
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
