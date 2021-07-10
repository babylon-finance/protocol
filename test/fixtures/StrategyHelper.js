const { ethers } = require('hardhat');
const { ONE_DAY_IN_SECONDS, STRATEGY_EXECUTE_MAP } = require('../../lib/constants.js');
const { impersonateAddress } = require('../../lib/rpc');
const addresses = require('../../lib/addresses');
const { getAssetWhale } = require('../../lib/whale');
const { increaseTime, getContract, from, eth } = require('../utils/test-helpers');

const DEFAULT_STRATEGY_PARAMS = [
  eth(10), // _maxCapitalRequested
  eth(0.1), // _stake
  ONE_DAY_IN_SECONDS * 30, // _strategyDuration
  eth(0.05), // 5% _expectedReturn
];

const DAI_STRATEGY_PARAMS = [
  eth(1e5), // _maxCapitalRequested
  eth(100), // _stake
  ONE_DAY_IN_SECONDS * 30, // _strategyDuration
  eth(0.05), // 5% _expectedReturn
];

const USDC_STRATEGY_PARAMS = [
  from(1e8 * 1e6), // _maxCapitalRequested
  from(100 * 1e6), // _stake
  ONE_DAY_IN_SECONDS * 30, // _strategyDuration
  eth(0.05), // 5% _expectedReturn
];

const WBTC_STRATEGY_PARAMS = [
  from(1000 * 1e8), // _maxCapitalRequested
  from(1e6), // _stake
  ONE_DAY_IN_SECONDS * 30, // _strategyDuration
  eth(0.05), // 5% _expectedReturn
];

const GARDEN_PARAMS_MAP = {
  [addresses.tokens.WETH]: DEFAULT_STRATEGY_PARAMS,
  [addresses.tokens.DAI]: DAI_STRATEGY_PARAMS,
  [addresses.tokens.USDC]: USDC_STRATEGY_PARAMS,
  [addresses.tokens.WBTC]: WBTC_STRATEGY_PARAMS,
};

const STRAT_NAME_PARAMS = ['Strategy Name', 'STRT']; // [ NAME, SYMBOL ]
const NFT_ADDRESS = 'https://babylon.mypinata.cloud/ipfs/Qmc7MfvuCkhA8AA2z6aBzmb5G4MaRfPeKgCVTWcKqU2tjB';

async function createStrategyWithBuyOperation(garden, signer, params, integration, data) {
  let ABI = ['function babylonFinanceStrategyOpData(address data, uint256 metadata)']; // 64 bytes
  let iface = new ethers.utils.Interface(ABI);
  let encodedData = iface.encodeFunctionData('babylonFinanceStrategyOpData', [...(data || [addresses.tokens.DAI, 0])]);
  const passedLongParams = [[0], [integration]];

  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedLongParams, encodedData);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('Strategy', lastStrategyAddr);

  return strategy;
}

async function createStrategyWithPoolOperation(garden, signer, params, integration, data) {
  const passedPoolParams = [[1], [integration]];
  let ABI = ['function babylonFinanceStrategyOpData(address data, uint256 metadata)']; // 64 bytes
  let iface = new ethers.utils.Interface(ABI);
  let encodedData = iface.encodeFunctionData('babylonFinanceStrategyOpData', [
    ...(data || [addresses.oneinch.pools.wethdai, 0]),
  ]);
  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedPoolParams, encodedData);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('Strategy', lastStrategyAddr);

  return strategy;
}

async function createStrategyWithVaultOperation(garden, signer, params, integration, data) {
  const passedYieldParams = [[2], [integration]];
  let ABI = ['function babylonFinanceStrategyOpData(address data, uint256 metadata)']; // 64 bytes
  let iface = new ethers.utils.Interface(ABI);
  let encodedData = iface.encodeFunctionData('babylonFinanceStrategyOpData', [
    ...(data || [addresses.yearn.vaults.ydai, 0]),
  ]);
  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedYieldParams, encodedData);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('Strategy', lastStrategyAddr);

  return strategy;
}

async function createStrategyWithLendOperation(garden, signer, params, integration, data) {
  const passedLendParams = [[3], [integration]];
  let ABI = ['function babylonFinanceStrategyOpData(address data, uint256 metadata)']; // 64 bytes
  let iface = new ethers.utils.Interface(ABI);
  let encodedData = iface.encodeFunctionData('babylonFinanceStrategyOpData', [...(data || [addresses.tokens.USDC, 0])]);

  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedLendParams, encodedData);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('Strategy', lastStrategyAddr);

  return strategy;
}

async function createStrategyWithLendAndBorrowOperation(
  garden,
  signer,
  params = DEFAULT_STRATEGY_PARAMS,
  integrations,
  data,
) {
  if (integrations.length !== 2 || data.length / 2 !== 2) {
    throw new Error('Need two integrations and data to create lend & borrow');
  }
  const passedLendBorrowParams = [[3, 4], integrations];
  let ABI = [
    'function babylonFinanceStrategyOpData(address data, uint256 metadata, address data2, uint256 metadata2 )',
  ]; // 64 bytes
  let iface = new ethers.utils.Interface(ABI);
  let encodedData = iface.encodeFunctionData('babylonFinanceStrategyOpData', [data[0], data[1], data[2], data[3]]);
  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedLendBorrowParams, encodedData);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('Strategy', lastStrategyAddr);

  return strategy;
}

async function createStrategyWithManyOperations(
  garden,
  signer,
  params = DEFAULT_STRATEGY_PARAMS,
  integrations,
  data,
  ops,
) {
  if (integrations.length !== data.length / 2) {
    throw new Error('Need data and integrations to match');
  }
  const passedParams = [ops, integrations];
  let ABI = [
    'function babylonFinanceStrategyOpData(address data, uint256 metadata, address data, uint256 metadata, address data, uint256 metadata)',
  ]; // 64 bytes
  let iface = new ethers.utils.Interface(ABI);
  let encodedData = iface.encodeFunctionData('babylonFinanceStrategyOpData', [
    data[0],
    data[1],
    data[2],
    data[3],
    data[4],
    data[5],
  ]);

  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedParams, encodedData);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('Strategy', lastStrategyAddr);

  return strategy;
}

async function deposit(garden, signers) {
  const reserveAsset = await garden.reserveAsset();
  const reserveContract = await ethers.getContractAt('IERC20', reserveAsset);
  let amount;
  switch (reserveAsset.toLowerCase()) {
    case addresses.tokens.USDC.toLowerCase():
      amount = ethers.BigNumber.from(2000 * 1e6);
      break;
    case addresses.tokens.DAI.toLowerCase():
      amount = ethers.utils.parseEther('2000');
      break;
    case addresses.tokens.WBTC.toLowerCase():
      amount = 1e6;
      break;
    default:
      amount = ethers.utils.parseEther('2');
  }

  for (const signer of signers.slice(0, 2)) {
    const isWeth = reserveAsset.toLowerCase() === addresses.tokens.WETH.toLowerCase();
    if (!isWeth) {
      await reserveContract.connect(signer).approve(garden.address, amount, { gasPrice: 0 });
    }
    await garden.connect(signer).deposit(
      amount,
      1,
      signer.getAddress(),
      false,
      isWeth
        ? {
            value: amount,
          }
        : {},
    );
  }
}

async function vote(strategy) {
  const garden = await strategy.garden();
  const gardenContract = await ethers.getContractAt('Garden', garden);

  const signers = await ethers.getSigners();
  const [, , , signer1, signer2] = signers;

  const signer1Balance = await gardenContract.balanceOf(signer1.getAddress());
  const signer2Balance = await gardenContract.balanceOf(signer2.getAddress());

  return (
    strategy
      // use keeper
      .connect((await ethers.getSigners())[1])
      .resolveVoting([signer1.getAddress(), signer2.getAddress()], [signer1Balance.div(3), signer2Balance.div(3)], 0, {
        gasPrice: 0,
      })
  );
}

async function executeStrategy(
  strategy,
  {
    /* Strategy default cooldown period */
    time = ONE_DAY_IN_SECONDS,
    amount = 0,
    fee = 0,
    gasPrice = 0,
  } = {},
) {
  const garden = await strategy.garden();
  const gardenContract = await ethers.getContractAt('Garden', garden);
  amount = amount || STRATEGY_EXECUTE_MAP[await gardenContract.reserveAsset()];
  const signers = await ethers.getSigners();
  if (time > 0) {
    await increaseTime(time);
  }
  return (
    strategy
      // use keeper
      .connect(signers[1])
      .executeStrategy(amount, fee, {
        gasPrice,
      })
  );
}

async function executeStrategyImmediate(strategy) {
  await executeStrategy(strategy, { time: 0 });
}

async function finalizeStrategy(
  strategy,
  {
    fee = 0,
    /* Strategy default duration */
    time = ONE_DAY_IN_SECONDS * 30,
    gasPrice = 0,
  } = {},
) {
  const signers = await ethers.getSigners();
  if (time > 0) {
    await increaseTime(time);
  }
  return (
    strategy
      // use keeper
      .connect(signers[1])
      .finalizeStrategy(fee, NFT_ADDRESS, { gasPrice })
  );
}

async function finalizeStrategyImmediate(strategy) {
  await finalizeStrategy(strategy, { time: 0 });
}

async function finalizeStrategyAfter30Days(strategy) {
  await finalizeStrategy(strategy, { time: ONE_DAY_IN_SECONDS * 30 });
}

async function finalizeStrategyAfterQuarter(strategy) {
  await finalizeStrategy(strategy, { time: ONE_DAY_IN_SECONDS * 90 });
}

async function finalizeStrategyAfter2Quarters(strategy) {
  await finalizeStrategy(strategy, { time: ONE_DAY_IN_SECONDS * 180 });
}

async function finalizeStrategyAfter3Quarters(strategy) {
  await finalizeStrategy(strategy, { time: ONE_DAY_IN_SECONDS * 270 });
}

async function finalizeStrategyAfter2Years(strategy) {
  await finalizeStrategy(strategy, { time: ONE_DAY_IN_SECONDS * 365 * 2 });
}

async function injectFakeProfits(strategy, amount) {
  const kind = await strategy.getOperationByIndex(0);
  if (kind[0] === 0) {
    let ABI = ['function babylonFinanceStrategyOpData(address data, uint256 metadata)']; // 64 bytes
    let iface = new ethers.utils.Interface(ABI);
    let decodedData = iface.decodeFunctionData('babylonFinanceStrategyOpData', await strategy.opEncodedData());

    const asset = await ethers.getContractAt('IERC20', decodedData[0]);
    const whaleAddress = getAssetWhale(asset.address);
    if (whaleAddress) {
      const whaleSigner = await impersonateAddress(whaleAddress);
      await asset.connect(whaleSigner).transfer(strategy.address, amount, {
        gasPrice: 0,
      });
    } else {
      console.error("Couldn't inject fake profits for", asset.address);
    }
  }
  if (kind[0] === 1) {
    let ABI = ['function babylonFinanceStrategyOpData(address data, uint256 metadata)']; // 64 bytes
    let iface = new ethers.utils.Interface(ABI);
    let decodedData = iface.decodeFunctionData('babylonFinanceStrategyOpData', await strategy.opEncodedData());

    const asset = await ethers.getContractAt('IERC20', decodedData[0]);
    const whaleAddress = await strategy.pool();
    const whaleSigner = await impersonateAddress(whaleAddress);
    await asset.connect(whaleSigner).transfer(strategy.address, amount, {
      gasPrice: 0,
    });
  }
  if (kind[0] === 2) {
    let ABI = ['function babylonFinanceStrategyOpData(address data, uint256 metadata)']; // 64 bytes
    let iface = new ethers.utils.Interface(ABI);
    let decodedData = iface.decodeFunctionData('babylonFinanceStrategyOpData', await strategy.opEncodedData());

    const asset = await ethers.getContractAt('IERC20', decodedData[0]);
    const whaleAddress = await strategy.yieldVault();
    const whaleSigner = await impersonateAddress(whaleAddress);
    await asset.connect(whaleSigner).transfer(strategy.address, amount, {
      gasPrice: 0,
    });
  }
}

async function substractFakeProfits(strategy, amount) {
  const kind = await strategy.getOperationByIndex(0);
  const strategyAddress = await impersonateAddress(strategy.address);
  if (kind[0] === 0) {
    let ABI = ['function babylonFinanceStrategyOpData(address data, uint256 metadata)']; // 64 bytes
    let iface = new ethers.utils.Interface(ABI);
    let decodedData = iface.decodeFunctionData('babylonFinanceStrategyOpData', await strategy.opEncodedData());
    const asset = await ethers.getContractAt('IERC20', decodedData[0]);
    const whaleAddress = getAssetWhale(asset.address);
    if (whaleAddress) {
      const whaleSigner = await impersonateAddress(whaleAddress);
      await asset.connect(strategyAddress).transfer(whaleSigner.address, amount, {
        gasPrice: 0,
      });
    } else {
      console.error("Couldn't reduce fake profits for", asset.address);
    }
  }
  if (kind[0] === 1) {
    let ABI = ['function babylonFinanceStrategyOpData(address data, uint256 metadata)']; // 64 bytes
    let iface = new ethers.utils.Interface(ABI);
    let decodedData = iface.decodeFunctionData('babylonFinanceStrategyOpData', await strategy.opEncodedData());

    const asset = await ethers.getContractAt('IERC20', decodedData[0]);
    const whaleAddress = await strategy.pool();
    const whaleSigner = await impersonateAddress(whaleAddress);
    await asset.connect(strategyAddress).transfer(whaleSigner.address, amount, {
      gasPrice: 0,
    });
  }
  if (kind[0] === 2) {
    let ABI = ['function babylonFinanceStrategyOpData(address data, uint256 metadata)']; // 64 bytes
    let iface = new ethers.utils.Interface(ABI);
    let decodedData = iface.decodeFunctionData('babylonFinanceStrategyOpData', await strategy.opEncodedData());

    const asset = await ethers.getContractAt('IERC20', decodedData[0]);
    const whaleAddress = await strategy.yieldVault();
    const whaleSigner = await impersonateAddress(whaleAddress);
    await asset.connect(strategyAddress).transfer(whaleSigner.address, amount, {
      gasPrice: 0,
    });
  }
}

async function createStrategy(kind, state, signers, integrations, garden, params, specificParams, customOps) {
  let strategy;

  const reserveAsset = await garden.reserveAsset();
  params = params || GARDEN_PARAMS_MAP[reserveAsset];

  switch (kind) {
    case 'buy':
      strategy = await createStrategyWithBuyOperation(garden, signers[0], params, integrations, specificParams);
      break;
    case 'lp':
      strategy = await createStrategyWithPoolOperation(garden, signers[0], params, integrations, specificParams);
      break;
    case 'vault':
      strategy = await createStrategyWithVaultOperation(garden, signers[0], params, integrations, specificParams);
      break;
    case 'lend':
      strategy = await createStrategyWithLendOperation(garden, signers[0], params, integrations, specificParams);
      break;
    case 'borrow':
      strategy = await createStrategyWithLendAndBorrowOperation(
        garden,
        signers[0],
        params,
        integrations,
        specificParams,
      );
      break;
    case 'custom':
      strategy = await createStrategyWithManyOperations(
        garden,
        signers[0],
        params,
        integrations,
        specificParams,
        customOps,
      );
      break;
    default:
      throw new Error(`Strategy type: "${kind}" not supported`);
  }
  if (strategy) {
    if (state === 'dataset') {
      return strategy;
    }
    await deposit(garden, signers);
    if (state === 'deposit') {
      return strategy;
    }
    await vote(strategy);
    if (state === 'vote') {
      return strategy;
    }
    await executeStrategy(strategy);
    if (state === 'active') {
      return strategy;
    }
    await finalizeStrategy(strategy);
  }

  return strategy;
}

async function getStrategy({
  garden,
  kind = 'buy',
  state = 'dataset',
  signers,
  integrations,
  params,
  specificParams,
} = {}) {
  const babController = await getContract('BabController', 'BabControllerProxy');
  const uniswapV3TradeIntegration = await getContract('UniswapV3TradeIntegration');
  const [deployer, keeper, owner, signer1, signer2, signer3] = await ethers.getSigners();
  const gardens = await babController.getGardens();

  return await createStrategy(
    kind,
    state,
    signers ? signers : [signer1, signer2, signer3],
    integrations ? integrations : uniswapV3TradeIntegration.address,
    garden ? garden : await ethers.getContractAt('Garden', gardens.slice(-1)[0]),
    params,
    specificParams,
  );
}

async function getStrategyState(strategy) {
  const [address, active, dataSet, finalized, executedAt, exitedAt, updatedAt] = await strategy.getStrategyState();

  return { address, active, dataSet, finalized, executedAt, exitedAt, updatedAt };
}

module.exports = {
  createStrategy,
  getStrategy,
  getStrategyState,
  DEFAULT_STRATEGY_PARAMS,
  DAI_STRATEGY_PARAMS,
  USDC_STRATEGY_PARAMS,
  executeStrategy,
  vote,
  executeStrategyImmediate,
  finalizeStrategy,
  finalizeStrategyImmediate,
  finalizeStrategyAfterQuarter,
  finalizeStrategyAfter2Quarters,
  finalizeStrategyAfter30Days,
  finalizeStrategyAfter3Quarters,
  finalizeStrategyAfter2Years,
  injectFakeProfits,
  substractFakeProfits,
  deposit,
};
