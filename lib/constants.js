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
const THREE = ethers.BigNumber.from(3);
const ZERO = Zero;
const MAX_INT_256 = '0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
const MIN_INT_256 = '-0x8000000000000000000000000000000000000000000000000000000000000000';
const ONE_DAY_IN_SECONDS = ethers.BigNumber.from(60 * 60 * 24);
const ONE_HOUR_IN_SECONDS = ethers.BigNumber.from(60 * 60);
const ONE_YEAR_IN_SECONDS = ethers.BigNumber.from(31557600);
const PRECISE_UNIT = WeiPerEther;
const ONE_ETH = WeiPerEther;
const MINUS_ONE_ETH = WeiPerEther.mul(-1);

const STRATEGY_TYPES = {
  LONG: 0,
  LIQUIDITY_POOL: 1,
  YIELD_FARM: 2,
};

const GARDEN_PARAMS = [
  eth('20'), // Max Deposit Limit
  eth('100'), // Min Liquidity Asset | ie: Uniswap Volume
  1, // Deposit Hardlock | 1 second
  eth('0.10'), // Min Contribution
  ONE_DAY_IN_SECONDS, // Strategy Cooldown Period
  eth('0.10'), // Min Voter Quorum | 10%
  ONE_DAY_IN_SECONDS * 3, // Min Strategy Duration
  ONE_DAY_IN_SECONDS * 365, // Max Strategy Duration
  1, // Min number of voters
  100, // Max number of members
];

const GARDEN_PARAMS_STABLE = [
  eth('200000'), // Max Deposit Limit
  eth('100'), // Min Liquidity Asset | ie: Uniswap Volume
  1, // Deposit Hardlock | 1 second
  eth('100'), // Min Contribution
  ONE_DAY_IN_SECONDS, // Strategy Cooldown Period
  eth('0.10'), // Min Voter Quorum | 10%
  ONE_DAY_IN_SECONDS * 3, // Min Strategy Duration
  ONE_DAY_IN_SECONDS * 365, // Max Strategy Duration
  1, // Min number of voters
  100, // Max number of members
];

const DAI_GARDEN_PARAMS = [
  eth('100000'), // Max Deposit Limit
  eth('1000000'), // Min Liquidity Asset | ie: Uniswap Volume
  1, // Deposit Hardlock | 1 second
  eth('100'), // Min Contribution
  ONE_DAY_IN_SECONDS, // Strategy Cooldown Period
  eth('0.10'), // Min Voter Quorum | 10%
  ONE_DAY_IN_SECONDS * 3, // Min Strategy Duration
  ONE_DAY_IN_SECONDS * 365, // Max Strategy Duration
  1, // Min number of voters
  100, // Max number of members
];

const USDC_GARDEN_PARAMS = [
  ethers.BigNumber.from(1e9 * 1e6), // Max Deposit Limit (6 decimals)
  ethers.BigNumber.from(1e6 * 1e6), // Min Liquidity Asset | ie: Uniswap Volume
  1, // Deposit Hardlock | 1 second
  ethers.BigNumber.from(100 * 1e6), // Min Contribution
  ONE_DAY_IN_SECONDS, // Strategy Cooldown Period
  eth('0.10'), // Min Voter Quorum | 10%
  ONE_DAY_IN_SECONDS * 3, // Min Strategy Duration
  ONE_DAY_IN_SECONDS * 365, // Max Strategy Duration
  1, // Min number of voters
  100, // Max number of members
];

const WBTC_GARDEN_PARAMS = [
  ethers.BigNumber.from(1e9), // Max Deposit Limit (6 decimals)
  ethers.BigNumber.from(1e5), // Min Liquidity Asset | ie: Uniswap Volume
  1, // Deposit Hardlock | 1 second
  ethers.BigNumber.from(1e6), // Min Contribution
  ONE_DAY_IN_SECONDS, // Strategy Cooldown Period
  eth('0.10'), // Min Voter Quorum | 10%
  ONE_DAY_IN_SECONDS * 3, // Min Strategy Duration
  ONE_DAY_IN_SECONDS * 365, // Max Strategy Duration
  1, // Min number of voters
  100, // Max number of members
];

const BABL_GARDEN_PARAMS = [
  eth('10000'), // Max Deposit Limit
  eth('10000'), // Min Liquidity Asset | ie: Uniswap Volume
  1, // Deposit Hardlock | 1 second
  eth('10'), // Min Contribution
  ONE_DAY_IN_SECONDS, // Strategy Cooldown Period
  eth('0.10'), // Min Voter Quorum | 10%
  ONE_DAY_IN_SECONDS * 3, // Min Strategy Duration
  ONE_DAY_IN_SECONDS * 365, // Max Strategy Duration
  1, // Min number of voters
  100, // Max number of members
];

const STRATEGY_EXECUTE_MAP = {
  [addresses.tokens.WETH]: eth(),
  [addresses.tokens.DAI]: eth(1000),
  [addresses.tokens.BABL]: eth(120),
  [addresses.tokens.USDC]: from(1000 * 1e6),
  [addresses.tokens.WBTC]: from(1e7), // Below '15e5' amount Uniswap throws 'revert UniswapV2Router: INSUFFICIENT_A_AMOUNT'
};

const GARDENS = [
  { token: addresses.tokens.WETH, name: 'WETH' },
  { token: addresses.tokens.DAI, name: 'DAI' },
  { token: addresses.tokens.USDC, name: 'USDC' },
  { token: addresses.tokens.WBTC, name: 'WBTC' },
];

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
  PROTOCOL_FEE,
  PROFIT_PROTOCOL_FEE,
  PROFIT_STRATEGIST_SHARE,
  PROFIT_STEWARD_SHARE,
  PROFIT_LP_SHARE,
};
