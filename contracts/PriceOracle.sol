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

    /* ============ Constructor ============ */

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

        // Check Synths
        // Check comp tokens
        // Cream prices 0xde19f5a7cF029275Be9cEC538E81Aa298E297266

        // other btcs, change pairs
        // other usd, change pair

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
}
