const { ethers } = require('hardhat');
const { ONE_DAY_IN_SECONDS } = require('../../utils/constants.js');
const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require('../../utils/system.js');
const { impersonateAddress } = require('../../utils/rpc');
const addresses = require('../../utils/addresses');

const DEFAULT_STRATEGY_PARAMS = [
  ethers.utils.parseEther('10'), // _maxCapitalRequested
  ethers.utils.parseEther('1'), // _stake
  ONE_DAY_IN_SECONDS * 30, // _investmentDuration
  ethers.utils.parseEther('0.05'), // 5% _expectedReturn
  ethers.utils.parseEther('1'), // _minRebalanceCapital
];

async function updateTWAPs(garden) {
  const controller = await ethers.getContractAt('BabController', await garden.controller());
  const priceOracle = await ethers.getContractAt('PriceOracle', await controller.getPriceOracle());
  const adapterAddress = (await priceOracle.getAdapters())[0];
  const adapter = await ethers.getContractAt('UniswapTWAP', adapterAddress);
  for (let i = 0; i < TWAP_ORACLE_GRANULARITY; i += 1) {
    await adapter.update(addresses.tokens.WETH, addresses.tokens.USDC);
    await adapter.update(addresses.tokens.WETH, addresses.tokens.DAI);
    // await adapter.update(addresses.tokens.WETH, addresses.tokens.WBTC);
    // await adapter.update(addresses.tokens.WETH, addresses.tokens.UNI);
    // await adapter.update(addresses.tokens.WETH, addresses.tokens.BAL);
    // await adapter.update(addresses.tokens.WETH, addresses.tokens.COMP);
    ethers.provider.send('evm_increaseTime', [TWAP_ORACLE_WINDOW / TWAP_ORACLE_GRANULARITY]);
  }
}

async function createLongStrategy(garden, integration, signer, params = DEFAULT_STRATEGY_PARAMS, longParams) {
  const passedLongParams = longParams || [addresses.tokens.DAI];
  await garden.connect(signer).addStrategy(0, integration, ...params, ...passedLongParams);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('LongStrategy', lastStrategyAddr);

  return strategy;
}

async function createPoolStrategy(garden, integration, signer, params = DEFAULT_STRATEGY_PARAMS, poolParams) {
  const passedPoolParams = poolParams || [addresses.balancer.pools.wethdai];
  await garden.connect(signer).addStrategy(1, integration, ...params, ...passedPoolParams);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('LiquidityPoolStrategy', lastStrategyAddr);

  return strategy;
}

async function createYieldStrategy(garden, integration, signer, params = DEFAULT_STRATEGY_PARAMS, yieldParams) {
  const passedYieldParams = yieldParams || [addresses.yearn.vaults.ydai];
  await garden.connect(signer).addStrategy(2, integration, ...params, ...passedYieldParams);
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('YieldFarmingStrategy', lastStrategyAddr);

  return strategy;
}

async function createLendStrategy(garden, integration, signer, params = DEFAULT_STRATEGY_PARAMS, lendParams) {
  const passedLendParams = lendParams || [addresses.tokens.USDC];
  await garden.connect(signer).addStrategy(3, integration, ...params, ...passedLendParams);
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

  return strategy.resolveVoting(
    [signer1.getAddress(), signer2.getAddress()],
    [signer1Balance, signer2Balance],
    signer1Balance.add(signer2Balance).toString(),
    signer1Balance.add(signer2Balance).toString(),
    0,
    { gasPrice: 0 },
  );
}

async function executeStrategy(garden, strategy, amount = ethers.utils.parseEther('1'), fee = 0) {
  ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);
  await updateTWAPs(garden);
  return strategy.executeInvestment(amount, fee, {
    gasPrice: 0,
  });
}

async function finalizeStrategy(garden, strategy, fee = 0) {
  ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);
  await updateTWAPs(garden);
  return strategy.finalizeInvestment(fee, { gasPrice: 0 });
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
  if (kind === 0) {
    strategy = await createLongStrategy(garden, integration, signers[0], params, specificParams);
  }
  if (kind === 1) {
    strategy = await createPoolStrategy(garden, integration, signers[0], params, specificParams);
  }
  if (kind === 2) {
    strategy = await createYieldStrategy(garden, integration, signers[0], params, specificParams);
  }
  if (kind === 3) {
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
    await executeStrategy(garden, strategy);
    if (state === 'active') {
      return strategy;
    }
    await finalizeStrategy(garden, strategy);
  }
  return strategy;
}

module.exports = {
  createStrategy,
  DEFAULT_STRATEGY_PARAMS,
  executeStrategy,
  finalizeStrategy,
  injectFakeProfits,
  deposit,
};
