/*
    Copyright 2021 Babylon Finance

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.7.6;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';

import {IPriceOracle} from './interfaces/IPriceOracle.sol';
import {ICToken} from './interfaces/external/compound/ICToken.sol';

import {PreciseUnitMath} from './lib/PreciseUnitMath.sol';
import {LowGasSafeMath as SafeMath} from './lib/LowGasSafeMath.sol';

/**
 * @title PriceOracle
 * @author Babylon Finance Protocol
 *
 * Uses Uniswap V3 to get a price of a token pair
 */
contract PriceOracle is Ownable, IPriceOracle {
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;
    using SafeMath for uint256;

    /* ============ State Variables ============ */

    /* ============ Constants ============ */

    // Address of Uniswap factory
    IUniswapV3Factory internal constant factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // the desired seconds agos array passed to the observe method
    uint32 private constant SECONDS_GRANULARITY = 30;

    uint24 private constant FEE_LOW = 500;
    uint24 private constant FEE_MEDIUM = 3000;
    uint24 private constant FEE_HIGH = 10000;
    int24 private constant maxTwapDeviation = 100;
    uint160 private constant maxLiquidityDeviationFactor = 50;
    int24 private constant baseThreshold = 1000;

    // Mapping of cToken addresses
    mapping(address => address) public cTokenToAsset;
    // Mapping of interest bearing aave tokens
    mapping(address => address) public aTokenToAsset;

    /* ============ Constructor ============ */

    constructor() {
        // TODO: get on chain
        cTokenToAsset[0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        cTokenToAsset[0x35A18000230DA775CAc24873d00Ff85BccdeD550] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // UNI
        cTokenToAsset[0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5] = WETH; // ETH
        cTokenToAsset[0x39AA39c021dfbaE8faC545936693aC917d5E7563] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        cTokenToAsset[0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        cTokenToAsset[0xccF4429DB6322D5C611ee964527D42E5d685DD6a] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
        cTokenToAsset[0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4] = 0xc00e94Cb662C3520282E6f5717214004A7f26888; // COMP
        cTokenToAsset[0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E] = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF; // BAT
        cTokenToAsset[0xFAce851a4921ce59e912d19329929CE6da6EB0c7] = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // LINK
        cTokenToAsset[0x158079Ee67Fce2f58472A96584A73C7Ab9AC95c1] = 0x1985365e9f78359a9B6AD760e32412f4a445E862; // REP
        cTokenToAsset[0xF5DCe57282A584D2746FaF1593d3121Fcac444dC] = 0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359; // SAI
        cTokenToAsset[0x12392F67bdf24faE0AF363c24aC620a2f67DAd86] = 0x0000000000085d4780B73119b644AE5ecd22b376; // TUSD
        cTokenToAsset[0xB3319f5D18Bc0D84dD1b4825Dcde5d5f7266d407] = 0xE41d2489571d322189246DaFA5ebDe1F4699F498; // ZRX

        // TODO: get on chain
        aTokenToAsset[0xFFC97d72E13E01096502Cb8Eb52dEe56f74DAD7B] = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9; // aave
        aTokenToAsset[0x272F97b7a56a387aE942350bBC7Df5700f8a4576] = 0xba100000625a3754423978a60c9317c58a424e3D; // bal
        aTokenToAsset[0x05Ec93c0365baAeAbF7AefFb0972ea7ECdD39CF1] = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF; // bat
        aTokenToAsset[0xA361718326c15715591c299427c62086F69923D9] = 0x4Fabb145d64652a948d72533023f6E7A623C7C53; // busd
        aTokenToAsset[0x028171bCA77440897B824Ca71D1c56caC55b68A3] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // dai
        aTokenToAsset[0xBcca60bB61934080951369a648Fb03DF4F96263C] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // usdc
        aTokenToAsset[0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // usdt
    }

    /* ============ External Functions ============ */

    /**
     * Returns the amount out corresponding to the amount in for a given token
     * @param _tokenIn              Address of the first token
     * @param _tokenOut             Address of the second token
     * @return price                Price of the pair
     */
    function getPrice(address _tokenIn, address _tokenOut) public view override returns (uint256 price) {
        bool found;
        uint256 price;
        int24 tick;
        IUniswapV3Pool pool;

        // Same asset. Returns base unit
        if (_tokenIn == _tokenOut) {
            return 10**18;
        }

        // Comp assets
        if (cTokenToAsset[_tokenIn] != address(0)) {
            uint256 exchangeRateNormalized = getCompoundExchangeRate(_tokenIn);
            return getPrice(cTokenToAsset[_tokenIn], _tokenOut).preciseMul(exchangeRateNormalized);
        }
        if (cTokenToAsset[_tokenOut] != address(0)) {
            uint256 exchangeRateNormalized = getCompoundExchangeRate(_tokenOut);
            return getPrice(_tokenIn, cTokenToAsset[_tokenOut]).preciseDiv(exchangeRateNormalized);
        }

        // aave tokens. 1 to 1 with underlying
        if (aTokenToAsset[_tokenIn] != address(0)) {
            return getPrice(aTokenToAsset[_tokenIn], _tokenOut);
        }
        if (aTokenToAsset[_tokenOut] != address(0)) {
            return getPrice(_tokenIn, aTokenToAsset[_tokenOut]);
        }
        // crTokens Cream prices 0xde19f5a7cF029275Be9cEC538E81Aa298E297266
        // Check Synths & integrate synths
        // Integrate lido

        // other btcs, change pairs & change path in uniswap trade
        // other usd, change pair & change path in uniswap trade
        // other eths, change pair & change path in uniswap trade

        if (_tokenIn != WETH && _tokenOut != WETH) {
            return getPrice(_tokenIn, WETH).preciseDiv(getPrice(_tokenOut, WETH));
        }
        // We try the low pool first
        (found, pool, tick) = checkPool(_tokenIn, _tokenOut, FEE_LOW);
        if (!found) {
            (found, pool, tick) = checkPool(_tokenIn, _tokenOut, FEE_MEDIUM);
        }
        if (!found) {
            (found, pool, tick) = checkPool(_tokenIn, _tokenOut, FEE_HIGH);
        }
        // No valid price
        require(found, 'Price not found');

        price = OracleLibrary
            .getQuoteAtTick(
            tick,
            // because we use 1e18 as a precision unit
            uint128(uint256(1e18).mul(10**(uint256(18).sub(ERC20(_tokenOut).decimals())))),
            _tokenIn,
            _tokenOut
        )
            .div(10**(uint256(18).sub(ERC20(_tokenIn).decimals())));
        return price;
    }

    function checkPool(
        address _tokenIn,
        address _tokenOut,
        uint24 fee
    )
        internal
        view
        returns (
            bool,
            IUniswapV3Pool,
            int24
        )
    {
        int24 tick;
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(_tokenIn, _tokenOut, fee));
        if (address(pool) != address(0)) {
            (, tick, , , , , ) = pool.slot0();
            return (_checkPrice(tick, pool), pool, tick);
        }
        return (false, IUniswapV3Pool(0), 0);
    }

    /* ============ Internal Functions ============ */

    /// @dev Revert if current price is too close to min or max ticks allowed
    /// by Uniswap, or if it deviates too much from the TWAP. Should be called
    /// whenever base and limit ranges are updated. In practice, prices should
    /// only become this extreme if there's no liquidity in the Uniswap pool.
    function _checkPrice(int24 mid, IUniswapV3Pool _pool) internal view returns (bool) {
        int24 tickSpacing = _pool.tickSpacing();
        // TODO: Add the other param from charm
        if (mid < TickMath.MIN_TICK + baseThreshold + tickSpacing) {
            // "price too low"
            return false;
        }
        if (mid > TickMath.MAX_TICK - baseThreshold - tickSpacing) {
            // "price too high"
            return false;
        }

        // Check TWAP deviation. This check prevents price manipulation before
        // the rebalance and also avoids rebalancing when price has just spiked.
        int56 twap = _getTwap(_pool);

        int56 deviation = mid > twap ? mid - twap : twap - mid;
        // Fail twap check
        return deviation < maxTwapDeviation;
    }

    // given the cumulative prices of the start and end of a period, and the length of the period, compute the average
    function _getTwap(IUniswapV3Pool _pool) private view returns (int56 twap) {
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = SECONDS_GRANULARITY;
        secondsAgo[1] = 0;
        // observe fails if the pair has no observations
        try _pool.observe(secondsAgo) returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        ) {
            return (tickCumulatives[1] - tickCumulatives[0]) / SECONDS_GRANULARITY;
        } catch {
            return 0;
        }
    }

    function getCompoundExchangeRate(address _asset) public view override returns (uint256) {
        uint256 exchangeRateNormalized = ICToken(_asset).exchangeRateStored();
        if (ERC20(cTokenToAsset[_asset]).decimals() > 8) {
            exchangeRateNormalized = exchangeRateNormalized.div(10**(ERC20(cTokenToAsset[_asset]).decimals() - 8));
        } else {
            exchangeRateNormalized = exchangeRateNormalized.mul(10**(8 - ERC20(cTokenToAsset[_asset]).decimals()));
        }
        return exchangeRateNormalized;
    }
}
