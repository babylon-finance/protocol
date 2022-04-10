const { ethers } = require('ethers');
const { from, eth } = require('./helpers');
const addresses = require('./addresses');

const { AddressZero, MaxUint256, One, Two, Zero, WeiPerEther } = ethers.constants;

const MODULE_STATE = {
  NONE: 0,
  PENDING: 1,
  INITIALIZED: 2,
};

const POSITION_STATE = {
  DEFAULT: 0,
  EXTERNAL: 1,
};

const ADDRESS_ZERO = AddressZero;
const EMPTY_BYTES = '0x';
const MAX_UINT_256 = MaxUint256;
const ONE = One;
const TWO = Two;
const now = new Date();
const NOW = Math.round(now.getTime() / 1000);
const THREE = from(3);
const ZERO = Zero;
const MAX_INT_256 = '0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
const MIN_INT_256 = '-0x8000000000000000000000000000000000000000000000000000000000000000';
const ONE_DAY_IN_SECONDS = from(60 * 60 * 24);
const ONE_HOUR_IN_SECONDS = from(60 * 60);
const ONE_YEAR_IN_SECONDS = from(31557600);
const PRECISE_UNIT = WeiPerEther;
const ONE_ETH = WeiPerEther;
const MINUS_ONE_ETH = WeiPerEther.mul(-1);

const STRATEGY_TYPES = {
  LONG: 0,
  LIQUIDITY_POOL: 1,
  YIELD_FARM: 2,
};

function getGardenParams({
  maxDepositLimit,
  minLiquidityAsset,
  depositHardlock,
  minContribution,
  strategyCooldownPeriod,
  minVotesQuorum,
  minStrategyDuration,
  maxStrategyDuration,
  minVoters,
  pricePerShareDecayRate,
  pricePerShareDelta,
  canMintNftAfter,
} = {}) {
  return [
    maxDepositLimit || eth(100), // Max Deposit Limit
    minLiquidityAsset || eth(100), // Min Liquidity Asset | ie: Uniswap Volume
    depositHardlock || 1, // Deposit Hardlock | 1 second
    minContribution || eth(0.1), // Min Contribution
    strategyCooldownPeriod || ONE_DAY_IN_SECONDS, // Strategy Cooldown Period
    minVotesQuorum || eth(0.1), // Min Voter Quorum | 10%
    minStrategyDuration || ONE_DAY_IN_SECONDS * 3, // Min Strategy Duration
    maxStrategyDuration || ONE_DAY_IN_SECONDS * 365, // Max Strategy Duration
    minVoters || 1, // Min number of voters
    pricePerShareDecayRate || eth(), // Decay rate of price per share
    pricePerShareDelta || eth(), // Base slippage for price per share
    canMintNftAfter || 1,
  ];
}

const GARDEN_PARAMS = getGardenParams();

const GARDEN_PARAMS_STABLE = getGardenParams({
  maxDepositLimit: eth(200000),
  minLiquidityAsset: eth(100),
  minContribution: eth(100),
});

const DAI_GARDEN_PARAMS = getGardenParams({
  maxDepositLimit: eth(100000),
  minLiquidityAsset: eth(1000000),
  minContribution: eth(100),
});

const USDC_GARDEN_PARAMS = getGardenParams({
  maxDepositLimit: from(1e9 * 1e6),
  minLiquidityAsset: from(1e6 * 1e6),
  minContribution: from(100 * 1e6),
});

const WBTC_GARDEN_PARAMS = getGardenParams({
  maxDepositLimit: from(1e9),
  minLiquidityAsset: from(1e5),
  minContribution: from(1e6),
});

const BABL_GARDEN_PARAMS = getGardenParams({
  maxDepositLimit: eth(20500),
  minLiquidityAsset: eth(10000),
  minContribution: eth(10),
});

const STRATEGY_EXECUTE_MAP = {
  [addresses.tokens.WETH]: eth(1),
  [addresses.tokens.DAI]: eth(1200),
  [addresses.tokens.BABL]: eth(10),
  [addresses.tokens.AAVE]: eth(10),
  [addresses.tokens.USDC]: from(1200 * 1e6),
  [addresses.tokens.WBTC]: from(1e7), // Below '15e5' amount Uniswap throws 'revert UniswapV2Router: INSUFFICIENT_A_AMOUNT'
};

const GARDENS = [
  { token: addresses.tokens.WETH, name: 'WETH' },
  { token: addresses.tokens.DAI, name: 'DAI' },
  { token: addresses.tokens.USDC, name: 'USDC' },
  { token: addresses.tokens.WBTC, name: 'WBTC' },
  { token: addresses.tokens.AAVE, name: 'AAVE' },
];

const STRATEGY_PARAMS = {
  strategyDuration: ONE_DAY_IN_SECONDS * 30,
  expectedReturn: eth(0.05),
  maxAllocationPercentage: eth(0.1),
  maxGasFeePercentage: eth(0.05),
  maxTradeSlippagePercentage: eth(0.09),
};

const WETH_STRATEGY_PARAMS = {
  maxCapitalRequested: eth(10),
  stake: eth(0.1),
  ...STRATEGY_PARAMS,
};

const DAI_STRATEGY_PARAMS = {
  maxCapitalRequested: eth(1e5),
  stake: eth(100),
  ...STRATEGY_PARAMS,
};

const USDC_STRATEGY_PARAMS = {
  maxCapitalRequested: from(1e8 * 1e6),
  stake: from(100 * 1e6),
  ...STRATEGY_PARAMS,
};

const WBTC_STRATEGY_PARAMS = {
  maxCapitalRequested: from(1e8),
  stake: from(1e6),
  strategyDuration: ONE_DAY_IN_SECONDS * 30,
  expectedReturn: eth(0.05),
  maxAllocationPercentage: eth(0.1),
  maxGasFeePercentage: eth(0.05),
  maxTradeSlippagePercentage: eth(0.09),
};

const BABL_STRATEGY_PARAMS = {
  maxCapitalRequested: eth(1e3),
  stake: from(1),
  ...STRATEGY_PARAMS,
};

const AAVE_STRATEGY_PARAMS = {
  maxCapitalRequested: eth(1e6),
  stake: from(1),
  ...STRATEGY_PARAMS,
};

const STRATEGY_PARAMS_MAP = {
  [addresses.tokens.WETH]: WETH_STRATEGY_PARAMS,
  [addresses.tokens.DAI]: DAI_STRATEGY_PARAMS,
  [addresses.tokens.USDC]: USDC_STRATEGY_PARAMS,
  [addresses.tokens.WBTC]: WBTC_STRATEGY_PARAMS,
  [addresses.tokens.BABL]: BABL_STRATEGY_PARAMS,
  [addresses.tokens.AAVE]: AAVE_STRATEGY_PARAMS,
};

const PROFIT_PROTOCOL_FEE = 5e16;
const PROTOCOL_FEE = 5e15;
const PROFIT_STRATEGIST_SHARE = eth('0.10'); // 10%
const PROFIT_STEWARD_SHARE = eth('0.05'); // 5%
const PROFIT_LP_SHARE = eth('0.80'); // 80%

module.exports = {
  ADDRESS_ZERO,
  EMPTY_BYTES,
  MAX_INT_256,
  MAX_UINT_256,
  MIN_INT_256,
  MODULE_STATE,
  NOW,
  ONE,
  ONE_DAY_IN_SECONDS,
  ONE_HOUR_IN_SECONDS,
  ONE_YEAR_IN_SECONDS,
  POSITION_STATE,
  PRECISE_UNIT,
  STRATEGY_TYPES,
  THREE,
  TWO,
  ZERO,
  GARDENS,
  GARDEN_PARAMS,
  GARDEN_PARAMS_STABLE,
  USDC_GARDEN_PARAMS,
  DAI_GARDEN_PARAMS,
  WBTC_GARDEN_PARAMS,
  BABL_GARDEN_PARAMS,
  STRATEGY_EXECUTE_MAP,
  STRATEGY_PARAMS_MAP,
  WETH_STRATEGY_PARAMS,
  PROTOCOL_FEE,
  PROFIT_PROTOCOL_FEE,
  PROFIT_STRATEGIST_SHARE,
  PROFIT_STEWARD_SHARE,
  PROFIT_LP_SHARE,
  getGardenParams,
};
