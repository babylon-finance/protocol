const { ethers } = require('ethers');
const { parse, from, eth } = require('./helpers');
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
  ethers.utils.parseEther('20'), // Max Deposit Limit
  ethers.utils.parseEther('100'), // Min Liquidity Asset | ie: Uniswap Volume
  1, // Deposit Hardlock | 1 second
  ethers.utils.parseEther('0.10'), // Min Contribution
  ONE_DAY_IN_SECONDS, // Strategy Cooldown Period
  ethers.utils.parseEther('0.10'), // Min Voter Quorum | 10%
  ONE_DAY_IN_SECONDS * 3, // Min Strategy Duration
  ONE_DAY_IN_SECONDS * 365, // Max Strategy Duration
  1, // Min number of voters
];

const GARDEN_PARAMS_STABLE = [
  ethers.utils.parseEther('200000'), // Max Deposit Limit
  ethers.utils.parseEther('100'), // Min Liquidity Asset | ie: Uniswap Volume
  1, // Deposit Hardlock | 1 second
  ethers.utils.parseEther('100'), // Min Contribution
  ONE_DAY_IN_SECONDS, // Strategy Cooldown Period
  ethers.utils.parseEther('0.10'), // Min Voter Quorum | 10%
  ONE_DAY_IN_SECONDS * 3, // Min Strategy Duration
  ONE_DAY_IN_SECONDS * 365, // Max Strategy Duration
  1, // Min number of voters
];

const DAI_GARDEN_PARAMS = [
  ethers.utils.parseEther('100000'), // Max Deposit Limit
  ethers.utils.parseEther('1000000'), // Min Liquidity Asset | ie: Uniswap Volume
  1, // Deposit Hardlock | 1 second
  ethers.utils.parseEther('100'), // Min Contribution
  ONE_DAY_IN_SECONDS, // Strategy Cooldown Period
  ethers.utils.parseEther('0.10'), // Min Voter Quorum | 10%
  ONE_DAY_IN_SECONDS * 3, // Min Strategy Duration
  ONE_DAY_IN_SECONDS * 365, // Max Strategy Duration
  1, // Min number of voters
];

const USDC_GARDEN_PARAMS = [
  ethers.BigNumber.from(1e5 * 1e6), // Max Deposit Limit (6 decimals)
  ethers.BigNumber.from(1e6 * 1e6), // Min Liquidity Asset | ie: Uniswap Volume
  1, // Deposit Hardlock | 1 second
  ethers.BigNumber.from(100 * 1e6), // Min Contribution
  ONE_DAY_IN_SECONDS, // Strategy Cooldown Period
  ethers.utils.parseEther('0.10'), // Min Voter Quorum | 10%
  ONE_DAY_IN_SECONDS * 3, // Min Strategy Duration
  ONE_DAY_IN_SECONDS * 365, // Max Strategy Duration
  1, // Min number of voters
];

const WBTC_GARDEN_PARAMS = [
  ethers.BigNumber.from(1e8), // Max Deposit Limit (6 decimals)
  ethers.BigNumber.from(300 * 1e8), // Min Liquidity Asset | ie: Uniswap Volume
  1, // Deposit Hardlock | 1 second
  ethers.BigNumber.from(1e6), // Min Contribution
  ONE_DAY_IN_SECONDS, // Strategy Cooldown Period
  ethers.utils.parseEther('0.10'), // Min Voter Quorum | 10%
  ONE_DAY_IN_SECONDS * 3, // Min Strategy Duration
  ONE_DAY_IN_SECONDS * 365, // Max Strategy Duration
  1, // Min number of voters
];

const STRATEGY_EXECUTE_MAP = {
  [addresses.tokens.WETH]: eth(),
  [addresses.tokens.DAI]: eth(1000),
  [addresses.tokens.USDC]: from(1000 * 1e6),
  [addresses.tokens.WBTC]: from(1e6),
};

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
  ONE_ETH,
  MINUS_ONE_ETH,
  GARDEN_PARAMS,
  GARDEN_PARAMS_STABLE,
  USDC_GARDEN_PARAMS,
  DAI_GARDEN_PARAMS,
  WBTC_GARDEN_PARAMS,
  STRATEGY_EXECUTE_MAP,
};
