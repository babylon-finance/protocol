const { ethers } = require('hardhat');
const { ONE_DAY_IN_SECONDS, ONE_ETH } = require('../../lib/constants.js');
const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require('../../lib/system.js');
const { impersonateAddress } = require('../../lib/rpc');
const addresses = require('../../lib/addresses');
const { getAssetWhale } = require('../../lib/whale');
const { increaseTime, from } = require('../utils/test-helpers');

const DEFAULT_STRATEGY_PARAMS = [
  ethers.utils.parseEther('10'), // _maxCapitalRequested
  ethers.utils.parseEther('0.1'), // _stake
  ONE_DAY_IN_SECONDS * 30, // _strategyDuration
  ethers.utils.parseEther('0.05'), // 5% _expectedReturn
  ethers.utils.parseEther('1'), // _minRebalanceCapital
];

const DAI_STRATEGY_PARAMS = [
  ethers.utils.parseEther('100000'), // _maxCapitalRequested
  ethers.utils.parseEther('100'), // _stake
  ONE_DAY_IN_SECONDS * 30, // _strategyDuration
  ethers.utils.parseEther('0.05'), // 5% _expectedReturn
  ethers.utils.parseEther('500'), // _minRebalanceCapital
];

const USDC_STRATEGY_PARAMS = [
  ethers.BigNumber.from(100000 * 1000000), // _maxCapitalRequested
  ethers.BigNumber.from(100 * 1000000), // _stake
  ONE_DAY_IN_SECONDS * 30, // _strategyDuration
  ethers.utils.parseEther('0.05'), // 5% _expectedReturn
  ethers.BigNumber.from(500 * 1000000), // _minRebalanceCapital
];

const STRAT_NAME_PARAMS = ['Strategy Name', 'STRT']; // [ NAME, SYMBOL ]
const NFT_ADDRESS = 'https://babylon.mypinata.cloud/ipfs/Qmc7MfvuCkhA8AA2z6aBzmb5G4MaRfPeKgCVTWcKqU2tjB';

async function updateTWAPs(gardenAddress) {
  const garden = await ethers.getContractAt('Garden', gardenAddress);
  const controller = await ethers.getContractAt('BabController', await garden.controller());
  const priceOracle = await ethers.getContractAt('PriceOracle', await controller.priceOracle());
  const adapterAddress = (await priceOracle.getAdapters())[0];
  const adapter = await ethers.getContractAt('UniswapTWAP', adapterAddress);
  for (let i = 0; i < TWAP_ORACLE_GRANULARITY; i += 1) {
    await adapter.update(addresses.tokens.WETH, addresses.tokens.USDC);
    await adapter.update(addresses.tokens.WETH, addresses.tokens.DAI);
    await increaseTime(from(TWAP_ORACLE_WINDOW).div(TWAP_ORACLE_GRANULARITY));
  }
}

async function createStrategyWithBuyOperation(garden, signer, params = DEFAULT_STRATEGY_PARAMS, integration, data) {
  const passedLongParams = [[0], [integration], [data || addresses.tokens.DAI]];
  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedLongParams);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('Strategy', lastStrategyAddr);

  return strategy;
}

async function createStrategyWithPoolOperation(garden, signer, params = DEFAULT_STRATEGY_PARAMS, integration, data) {
  const passedPoolParams = [[1], [integration], [data || addresses.oneinch.pools.wethdai]];
  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedPoolParams);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('Strategy', lastStrategyAddr);

  return strategy;
}

async function createStrategyWithVaultOperation(garden, signer, params = DEFAULT_STRATEGY_PARAMS, integration, data) {
  const passedYieldParams = [[2], [integration], [data || addresses.yearn.vaults.ydai]];
  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedYieldParams);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('Strategy', lastStrategyAddr);

  return strategy;
}

async function createStrategyWithLendOperation(garden, signer, params = DEFAULT_STRATEGY_PARAMS, integration, data) {
  const passedLendParams = [[3], [integration], [data || addresses.tokens.USDC]];
  await garden.connect(signer).addStrategy(...STRAT_NAME_PARAMS, params, ...passedLendParams);
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
      amount = ethers.BigNumber.from(400 * 1000000);
      break;
    case addresses.tokens.DAI.toLowerCase():
      amount = ethers.utils.parseEther('1000');
      break;
    default:
      amount = ethers.utils.parseEther('2');
  }
  if (reserveAsset.toLowerCase() !== addresses.tokens.WETH.toLowerCase()) {
    await reserveContract.connect(signers[0]).approve(garden.address, amount, { gasPrice: 0 });
  }
  await garden.connect(signers[0]).deposit(amount, 1, signers[0].getAddress(), {
    value: amount,
  });
  if (reserveAsset.toLowerCase() !== addresses.tokens.WETH.toLowerCase()) {
    await reserveContract.connect(signers[1]).approve(garden.address, amount, { gasPrice: 0 });
  }
  await garden.connect(signers[1]).deposit(amount, 1, signers[1].getAddress(), {
    value: amount,
  });
}

async function vote(garden, signers, strategy) {
  const [signer1, signer2] = signers;

  const signer1Balance = await garden.balanceOf(signer1.getAddress());
  const signer2Balance = await garden.balanceOf(signer2.getAddress());

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
    amount = ONE_ETH,
    fee = 0,
    TWAPs = true,
    gasPrice = 0,
  } = {},
) {
  const signers = await ethers.getSigners();
  if (time > 0) {
    await increaseTime(time);
  }
  if (TWAPs) {
    await updateTWAPs(await strategy.garden());
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
    TWAPs = true,
    gasPrice = 0,
  } = {},
) {
  const signers = await ethers.getSigners();
  if (time > 0) {
    await increaseTime(time);
  }
  // increaseTime(ONE_DAY_IN_SECONDS * 90);
  if (TWAPs) {
    await updateTWAPs(await strategy.garden());
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
  const kind = await strategy.opTypes(0);
  if (kind === 0) {
    const asset = await ethers.getContractAt('IERC20', await strategy.opDatas(0));
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
    const asset = await ethers.getContractAt('IERC20', await strategy.opDatas(0));
    const whaleAddress = await strategy.pool();
    const whaleSigner = await impersonateAddress(whaleAddress);
    await asset.connect(whaleSigner).transfer(strategy.address, amount, {
      gasPrice: 0,
    });
  }
  if (kind === 2) {
    const asset = await ethers.getContractAt('IERC20', await strategy.opDatas(0));
    const whaleAddress = await strategy.yieldVault();
    const whaleSigner = await impersonateAddress(whaleAddress);
    await asset.connect(whaleSigner).transfer(strategy.address, amount, {
      gasPrice: 0,
    });
  }
}

async function createStrategy(
  kind,
  state,
  signers,
  integration,
  garden,
  params = DEFAULT_STRATEGY_PARAMS,
  specificParams,
) {
  let strategy;

  switch (kind) {
    case 'buy':
      strategy = await createStrategyWithBuyOperation(garden, signers[0], params, integration, specificParams);
      break;
    case 'lp':
      strategy = await createStrategyWithPoolOperation(garden, signers[0], params, integration, specificParams);
      break;
    case 'vault':
      strategy = await createStrategyWithVaultOperation(garden, signers[0], params, integration, specificParams);
      break;
    case 'lend':
      strategy = await createStrategyWithLendOperation(garden, signers[0], params, integration, specificParams);
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
    await vote(garden, signers, strategy);
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

module.exports = {
  createStrategy,
  DEFAULT_STRATEGY_PARAMS,
  DAI_STRATEGY_PARAMS,
  USDC_STRATEGY_PARAMS,
  executeStrategy,
  executeStrategyImmediate,
  finalizeStrategy,
  finalizeStrategyImmediate,
  finalizeStrategyAfterQuarter,
  finalizeStrategyAfter2Quarters,
  finalizeStrategyAfter30Days,
  finalizeStrategyAfter3Quarters,
  finalizeStrategyAfter2Years,
  injectFakeProfits,
  deposit,
  updateTWAPs,
};
