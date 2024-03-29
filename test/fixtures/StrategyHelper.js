const { ethers } = require('hardhat');
const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS, STRATEGY_EXECUTE_MAP, STRATEGY_PARAMS_MAP } = require('lib/constants.js');
const { impersonateAddress } = require('lib/rpc');
const addresses = require('lib/addresses');
const { getAssetWhale } = require('lib/whale');
const { increaseTime, normalizeDecimals, getERC20, getContract, parse, from, eth } = require('utils/test-helpers');

function encodeData(data) {
  return new ethers.utils.AbiCoder().encode(
    data.map((int, i) => (i % 2 === 0 ? 'address' : 'uint256')),
    data,
  );
}

const STRAT_NAME_PARAMS = ['Strategy Name', 'STRT']; // [ NAME, SYMBOL ]
const NFT_ADDRESS = 'https://babylon.mypinata.cloud/ipfs/Qmc7MfvuCkhA8AA2z6aBzmb5G4MaRfPeKgCVTWcKqU2tjB';

async function createStrategyWithBuyOperation(garden, signer, params, integration, data) {
  const passedLongParams = [[0], [integration]];
  const encoded = encodeData(data || [addresses.tokens.DAI, 0]);
  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedLongParams, encoded);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  return await ethers.getContractAt('Strategy', lastStrategyAddr);
}

async function createStrategyWithPoolOperation(garden, signer, params, integration, data) {
  const passedPoolParams = [[1], [integration]];
  const encoded = encodeData(data || [addresses.oneinch.pools.wethdai, 0]);
  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedPoolParams, encoded);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];
  return await ethers.getContractAt('Strategy', lastStrategyAddr);
}

async function createStrategyWithVaultOperation(garden, signer, params, integration, data) {
  const passedYieldParams = [[2], [integration]];
  const encoded = encodeData(data || [addresses.yearn.daiVault, 0]);
  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedYieldParams, encoded);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  return await ethers.getContractAt('Strategy', lastStrategyAddr);
}
async function createStrategyWithCustomOperation(garden, signer, params, integration, data) {
  const passedCustomParams = [[5], [integration]];
  const encoded = encodeData(data || [ADDRESS_ZERO, 0]);
  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedCustomParams, encoded);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  return await ethers.getContractAt('Strategy', lastStrategyAddr);
}

async function createStrategyWithLendOperation(garden, signer, params, integration, data) {
  const passedLendParams = [[3], [integration]];
  const encoded = encodeData(data || [addresses.tokens.USDC, 0]);
  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedLendParams, encoded);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  return await ethers.getContractAt('Strategy', lastStrategyAddr);
}

async function createStrategyWithLendAndBorrowOperation(garden, signer, params, integrations, data) {
  if (integrations.length !== 2 || data.length / 2 !== 2) {
    throw new Error('Need two integrations and data to create lend & borrow');
  }
  const passedLendBorrowParams = [[3, 4], integrations];
  const encoded = encodeData(data);
  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedLendBorrowParams, encoded);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  return await ethers.getContractAt('Strategy', lastStrategyAddr);
}

async function createStrategyWithAddAndDepositOperation(garden, signer, params, integrations, data) {
  if (integrations.length !== 2 || data.length / 2 !== 2) {
    throw new Error('Need two integrations and data to create lend & borrow');
  }
  const passedAddandDepositParams = [[1, 2], integrations];
  const encoded = encodeData(data);
  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedAddandDepositParams, encoded);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  return await ethers.getContractAt('Strategy', lastStrategyAddr);
}

async function createStrategyWithManyOperations(garden, signer, params, integrations, data, ops) {
  if (integrations.length !== data.length / 2) {
    throw new Error('Need data and integrations to match');
  }
  const passedParams = [ops, integrations];
  const encoded = encodeData(data);
  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedParams, encoded);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];
  return await ethers.getContractAt('Strategy', lastStrategyAddr);
}

async function deposit(garden, signers) {
  const gardenValuer = await getContract('GardenValuer');
  const reserveAsset = await garden.reserveAsset();
  const reserveContract = await getERC20(reserveAsset);
  let amount;
  switch (reserveAsset.toLowerCase()) {
    case addresses.tokens.USDC.toLowerCase():
      amount = ethers.BigNumber.from(2000 * 1e6);
      break;
    case addresses.tokens.BABL.toLowerCase():
      amount = STRATEGY_EXECUTE_MAP[reserveAsset];
      break;
    case addresses.tokens.AAVE.toLowerCase():
      amount = STRATEGY_EXECUTE_MAP[reserveAsset];
      break;
    case addresses.tokens.DAI.toLowerCase():
      amount = eth(2000);
      break;
    case addresses.tokens.WBTC.toLowerCase():
      amount = 1e6;
      break;
    default:
      amount = eth(2);
  }

  for (const signer of signers.slice(0, 2)) {
    const isWeth = reserveAsset.toLowerCase() === addresses.tokens.WETH.toLowerCase();
    if (!isWeth) {
      await reserveContract.connect(signer).approve(garden.address, amount, { gasPrice: 0 });
    }
    await garden.connect(signer).deposit(
      amount,
      amount,
      signer.getAddress(),
      ADDRESS_ZERO,
      isWeth
        ? {
            value: amount,
          }
        : {},
    );
  }
}

async function vote(strategy, signers) {
  const garden = await strategy.garden();
  const gardenContract = await ethers.getContractAt('IGarden', garden);

  const [signer1, signer2] = signers;

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
    gasLimit = 9500000,
  } = {},
) {
  const garden = await strategy.garden();
  const gardenContract = await ethers.getContractAt('IGarden', garden);
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
        gasLimit,
      })
  );
}

async function signalUnlockStrategy(strategy, { fee = 0, gasPrice = 0, gasLimit = 9500000 } = {}) {
  const signers = await ethers.getSigners();
  return (
    strategy
      // use keeper
      .connect(signers[1])
      .signalUnlock(fee, {
        gasPrice,
        gasLimit,
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
    /* Strategy default minReserveOut */
    minReserveOut = 0,
    gasPrice = 0,
    gasLimit = 9500000,
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
      .finalizeStrategy(fee, NFT_ADDRESS, minReserveOut, { gasPrice, gasLimit })
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
  const kind = (await strategy.getOperationByIndex(0))[0];
  if (kind === 0) {
    const decoded = new ethers.utils.AbiCoder().decode(['address', 'uint256'], await strategy.opEncodedData());
    const asset = await getERC20(decoded[0]);
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
  if (kind === 1) {
    const decoded = new ethers.utils.AbiCoder().decode(['address', 'uint256'], await strategy.opEncodedData());

    const asset = await getERC20(decoded[0]);
    const whaleAddress = await strategy.pool();
    const whaleSigner = await impersonateAddress(whaleAddress);
    await asset.connect(whaleSigner).transfer(strategy.address, amount, {
      gasPrice: 0,
    });
  }
  if (kind === 2) {
    const decoded = new ethers.utils.AbiCoder().decode(['address', 'uint256'], await strategy.opEncodedData());

    const asset = await getERC20(decoded[0]);
    const whaleAddress = await strategy.yieldVault();
    const whaleSigner = await impersonateAddress(whaleAddress);
    await asset.connect(whaleSigner).transfer(strategy.address, amount, {
      gasPrice: 0,
    });
  }
}

async function substractFakeProfits(strategy, amount) {
  const kind = (await strategy.getOperationByIndex(0))[0];
  const strategyAddress = await impersonateAddress(strategy.address);
  if (kind === 0) {
    const decoded = new ethers.utils.AbiCoder().decode(['address', 'uint256'], await strategy.opEncodedData());

    const asset = await getERC20(decoded[0]);
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
  if (kind === 1) {
    const decoded = new ethers.utils.AbiCoder().decode(['address', 'uint256'], await strategy.opEncodedData());

    const asset = await getERC20(decoded[0]);
    const whaleAddress = await strategy.pool();
    const whaleSigner = await impersonateAddress(whaleAddress);
    await asset.connect(strategyAddress).transfer(whaleSigner.address, amount, {
      gasPrice: 0,
    });
  }
  if (kind === 2) {
    const decoded = new ethers.utils.AbiCoder().decode(['address', 'uint256'], await strategy.opEncodedData());

    const asset = await getERC20(decoded[0]);
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

  params = params || strategyParamsToArray(STRATEGY_PARAMS_MAP[reserveAsset]);

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
    case 'custom':
      strategy = await createStrategyWithCustomOperation(garden, signers[0], params, integrations, specificParams);
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
    case 'lpStack':
      strategy = await createStrategyWithAddAndDepositOperation(
        garden,
        signers[0],
        params,
        integrations,
        specificParams,
      );
      break;
    case 'complex':
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
    await vote(strategy, signers);
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
  const [, , , signer1, signer2, signer3] = await ethers.getSigners();
  const gardens = await babController.getGardens();
  garden = garden || (await ethers.getContractAt('IGarden', gardens.slice(-1)[0]));
  const reserveAsset = await garden.reserveAsset();

  params = { ...STRATEGY_PARAMS_MAP[reserveAsset], ...params };

  return await createStrategy(
    kind,
    state,
    signers || [signer1, signer2, signer3],
    integrations || uniswapV3TradeIntegration.address,
    garden,
    strategyParamsToArray(params),
    specificParams,
  );
}

function strategyParamsToArray({
  maxCapitalRequested,
  stake,
  strategyDuration,
  expectedReturn,
  maxAllocationPercentage,
  maxGasFeePercentage,
  maxTradeSlippagePercentage,
}) {
  return [
    maxCapitalRequested,
    stake,
    strategyDuration,
    expectedReturn,
    maxAllocationPercentage,
    maxGasFeePercentage,
    maxTradeSlippagePercentage,
  ];
}

async function getStrategyState(strategy) {
  const [address, active, dataSet, finalized, executedAt, exitedAt, updatedAt] = await strategy.getStrategyState();

  return { address, active, dataSet, finalized, executedAt, exitedAt, updatedAt };
}

module.exports = {
  strategyParamsToArray,
  createStrategy,
  getStrategy,
  getStrategyState,
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
  signalUnlockStrategy,
  injectFakeProfits,
  substractFakeProfits,
  deposit,
};
