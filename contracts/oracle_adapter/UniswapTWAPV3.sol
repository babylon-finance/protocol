/*
    Copyright 2021 Babylon Finance

    Modified from Uniswap TWAPs

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

import 'hardhat/console.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol';

import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';

import {IBabController} from '../interfaces/IBabController.sol';
import {IOracleAdapter} from '../interfaces/IOracleAdapter.sol';

/**
 * @title UniswapTWAPV3
 * @author Babylon Finance Protocol
 *
 * Uses uniswap V3 to get the price of a token pair
 */
contract UniswapTWAPV3 is Ownable, IOracleAdapter {
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;
    using SafeMath for uint256;

    /* ============ State Variables ============ */

    // Instance of the Controller contract
    IBabController public controller;

    // Name to identify this adapter
    string public constant name = 'uniswapTwapV3';

    // Address of Uniswap factory
    IUniswapV3Factory public immutable factory;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // the desired seconds agos array passed to the observe method
    uint32[] public secondsAgo = new uint32[](2);
    uint32 public constant SECONDS_GRANULARITY = 30;

    uint24 private constant FEE_LOW = 500;
    uint24 private constant FEE_MEDIUM = 3000;
    uint24 private constant FEE_HIGH = 10000;
    int24 private maxTwapDeviation = 100;
    uint160 private maxLiquidityDeviationFactor = 50;
    int24 private baseThreshold = 1000;

    /* ============ Constructor ============ */

    /**
     * Set state variables
     *
     * @param _controller         Instance of controller contract
     * @param _factory            Address of Uniswap factory
     */
    constructor(address _controller, address _factory) {
        factory = IUniswapV3Factory(_factory);
        controller = IBabController(_controller);
        secondsAgo[0] = SECONDS_GRANULARITY;
        secondsAgo[1] = 0;
    }

    /* ============ External Functions ============ */

    /**
     * Returns the amount out corresponding to the amount in for a given token
     * @param _tokenIn              Address of the first token
     * @param _tokenOut             Address of the second token
     * @return found               Whether or not the price as found
     */
    function getPrice(address _tokenIn, address _tokenOut) external view override returns (bool found, uint256 price) {
        int24 tick;
        bool found = false;
        // We try the low pool first
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(_tokenIn, _tokenOut, FEE_LOW));
        if (address(pool) != address(0)) {
            (, tick, , , , , ) = pool.slot0();
            found = _checkPrice(tick, pool);
        }
        if (!found) {
            pool = IUniswapV3Pool(factory.getPool(_tokenIn, _tokenOut, FEE_MEDIUM));
            if (address(pool) != address(0)) {
                (, tick, , , , , ) = pool.slot0();
                found = _checkPrice(tick, pool);
            }
        }
        if (!found) {
            pool = IUniswapV3Pool(factory.getPool(_tokenIn, _tokenOut, FEE_HIGH));
            if (address(pool) != address(0)) {
                (, tick, , , , , ) = pool.slot0();
                found = _checkPrice(tick, pool);
            }
        }
        // No valid price
        if (!found) {
            return (false, 0);
        }

        int256 twapTick = OracleLibrary.consult(address(pool), SECONDS_GRANULARITY);
        uint256 price =
            OracleLibrary
                .getQuoteAtTick(
                int24(twapTick),
                // because we use 1e18 as a precision unit
                uint128(uint256(1e18).mul(10**(uint256(18).sub(ERC20(_tokenOut).decimals())))),
                _tokenIn,
                _tokenOut
            )
                .div(10**(uint256(18).sub(ERC20(_tokenIn).decimals())));
        return (true, price);
    }

    function update(address tokenA, address tokenB) external override {}

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
        (int56 twap, ) = _getTwap(_pool);
        int56 deviation = mid > twap ? mid - twap : twap - mid;
        // Fail twap check
        return deviation < maxTwapDeviation;
    }

    // given the cumulative prices of the start and end of a period, and the length of the period, compute the average
    // price in terms of how much amount out is received for the amount in
    function _getTwap(IUniswapV3Pool _pool) private view returns (int56 amountOut, uint160 liquidity) {
        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) =
            _pool.observe(secondsAgo);
        liquidity =
            (secondsPerLiquidityCumulativeX128s[1] - secondsPerLiquidityCumulativeX128s[0]) /
            SECONDS_GRANULARITY;
        amountOut = (tickCumulatives[1] - tickCumulatives[0]) / SECONDS_GRANULARITY;
    }
}
