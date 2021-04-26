const { ethers } = require('hardhat');
const { ONE_DAY_IN_SECONDS, ONE_ETH } = require('../../lib/constants.js');
const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require('../../lib/system.js');
const { impersonateAddress } = require('../../lib/rpc');
const addresses = require('../../lib/addresses');
const { increaseTime, from } = require('../utils/test-helpers');

const DEFAULT_STRATEGY_PARAMS = [
  ethers.utils.parseEther('10'), // _maxCapitalRequested
  ethers.utils.parseEther('0.5'), // _stake
  ONE_DAY_IN_SECONDS * 30, // _strategyDuration
  ethers.utils.parseEther('0.05'), // 5% _expectedReturn
  ethers.utils.parseEther('1'), // _minRebalanceCapital
];

const NFT_STRAT_PARAMS = ['Strat Name', 'STRT'];
const NFT_ADDRESS = 'http://null.dev';

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

async function createLongStrategy(garden, integration, signer, params = DEFAULT_STRATEGY_PARAMS, longParams) {
  const passedLongParams = longParams || [addresses.tokens.DAI];
  await garden.connect(signer).addStrategy(0, integration, ...params, ...passedLongParams, ...NFT_STRAT_PARAMS);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('LongStrategy', lastStrategyAddr);

  return strategy;
}

async function createPoolStrategy(garden, integration, signer, params = DEFAULT_STRATEGY_PARAMS, poolParams) {
  const passedPoolParams = poolParams || [addresses.balancer.pools.wethdai];
  await garden.connect(signer).addStrategy(1, integration, ...params, ...passedPoolParams, ...NFT_STRAT_PARAMS);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('LiquidityPoolStrategy', lastStrategyAddr);

  return strategy;
}

async function createYieldStrategy(garden, integration, signer, params = DEFAULT_STRATEGY_PARAMS, yieldParams) {
  const passedYieldParams = yieldParams || [addresses.yearn.vaults.ydai];
  await garden.connect(signer).addStrategy(2, integration, ...params, ...passedYieldParams, ...NFT_STRAT_PARAMS);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('YieldFarmingStrategy', lastStrategyAddr);

  return strategy;
}

async function createLendStrategy(garden, integration, signer, params = DEFAULT_STRATEGY_PARAMS, lendParams) {
  const passedLendParams = lendParams || [addresses.tokens.USDC];
  await garden.connect(signer).addStrategy(3, integration, ...params, ...passedLendParams, ...NFT_STRAT_PARAMS);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('LendStrategy', lastStrategyAddr);

  return strategy;
}

async function deposit(garden, signers) {
  await garden.connect(signers[0]).deposit(ethers.utils.parseEther('2'), 1, signers[0].getAddress(), {
    value: ethers.utils.parseEther('2'),
  });
  await garden.connect(signers[1]).deposit(ethers.utils.parseEther('2'), 1, signers[1].getAddress(), {
    value: ethers.utils.parseEther('2'),
  });
}

async function vote(garden, signers, strategy) {
  const [signer1, signer2] = signers;

  const signer1Balance = await garden.balanceOf(signer1.getAddress());
  const signer2Balance = await garden.balanceOf(signer2.getAddress());

  return (
    strategy
      // use keeper
      .connect(signer1)
      .resolveVoting(
        [signer1.getAddress(), signer2.getAddress()],
        [signer1Balance.div(3), signer2Balance.div(3)],
        signer1Balance.add(signer2Balance).toString(),
        signer1Balance.add(signer2Balance).toString(),
        0,
        { gasPrice: 0 },
      )
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
  const kind = await strategy.kind();
  if (kind === 0) {
    const asset = await ethers.getContractAt('IERC20', await strategy.longToken());
    const whaleAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'; // Has DAI
    const whaleSigner = await impersonateAddress(whaleAddress);
    await asset.connect(whaleSigner).transfer(strategy.address, amount, {
      gasPrice: 0,
    });
  }
  if (kind === 1) {
    const asset = await ethers.getContractAt('IERC20', await strategy.pool());
    const whaleAddress = await strategy.pool();
    const whaleSigner = await impersonateAddress(whaleAddress);
    await asset.connect(whaleSigner).transfer(strategy.address, amount, {
      gasPrice: 0,
    });
  }
  if (kind === 2) {
    const asset = await ethers.getContractAt('IERC20', await strategy.yieldVault());
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
  if (kind === 'long') {
    strategy = await createLongStrategy(garden, integration, signers[0], params, specificParams);
  }
  if (kind === 'pool') {
    strategy = await createPoolStrategy(garden, integration, signers[0], params, specificParams);
  }
  if (kind === 'yield') {
    strategy = await createYieldStrategy(garden, integration, signers[0], params, specificParams);
  }
  if (kind === 'lend') {
    strategy = await createLendStrategy(garden, integration, signers[0], params, specificParams);
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
