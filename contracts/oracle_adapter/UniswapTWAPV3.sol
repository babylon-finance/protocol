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
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

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

    // the desired seconds agos array passed to the observe method
    uint32[] public secondsAgo = new uint32[](2);
    uint32 public constant SECONDS_GRANULARITY = 30;

    uint24 private constant FEE_LOW = 500;
    uint24 private constant FEE_MEDIUM = 3000;
    uint24 private constant FEE_HIGH = 10000;
    int24 private maxTwapDeviation = 100;

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
     * @param tokenIn              Address of the first token
     * @param tokenOut             Address of the second token
     * @return found               Whether or not the price as found
     * @return amountOut            How many tokenOut are one tokenIn
     */
    function getPrice(address tokenIn, address tokenOut)
        external
        view
        override
        returns (bool found, uint256 amountOut)
    {
        IUniswapV3Pool poolLow = IUniswapV3Pool(factory.getPool(tokenIn, tokenOut, FEE_LOW));
        IUniswapV3Pool poolLowAlt = IUniswapV3Pool(factory.getPool(tokenOut, tokenIn, FEE_LOW));
        IUniswapV3Pool poolMedium = IUniswapV3Pool(factory.getPool(tokenIn, tokenOut, FEE_MEDIUM));
        IUniswapV3Pool poolHigh = IUniswapV3Pool(factory.getPool(tokenIn, tokenOut, FEE_HIGH));
        console.log('pool low', address(poolLow));
        console.log('pool low alt', address(poolLowAlt));
        console.log('pool medium', address(poolMedium));
        console.log('pool high', address(poolHigh));
        console.log('after observe');
        (uint160 sqrtPriceX96Low, int24 tick,,,,,) =  poolLow.slot0();
        (uint160 sqrtPriceX96Medium,,,,,,) =  poolLow.slot0();
        (uint160 sqrtPriceX96High,,,,,,) =  poolLow.slot0();
        console.log('tick');
        console.logInt(int256(tick));
        console.log('sqrtPriceX96Low', sqrtPriceX96Low);
        console.log('sqrtPriceX96Low', uint(sqrtPriceX96Low));
        console.log('sqrtPriceX96Medium', sqrtPriceX96Medium);
        console.log('sqrtPriceX96High', sqrtPriceX96High);
        //_checkMid(mid, poolLow);
        return (true, uint(sqrtPriceX96Low).mul(uint(sqrtPriceX96Low)).mul(1e18) >> (96 * 2));
    }

    function update(address tokenA, address tokenB) external override {}

    /* ============ Internal Functions ============ */

    /// @dev Get current price from pool
    function _mid(IUniswapV3Pool _pool) internal view returns (int24 mid) {
        (, mid, , , , , ) = _pool.slot0();
    }

    /// @dev Revert if current price is too close to min or max ticks allowed
    /// by Uniswap, or if it deviates too much from the TWAP. Should be called
    /// whenever base and limit ranges are updated. In practice, prices should
    /// only become this extreme if there's no liquidity in the Uniswap pool.
    function _checkMid(int24 mid, IUniswapV3Pool _pool) internal view {
        int24 tickSpacing = _pool.tickSpacing();
        require(mid > TickMath.MIN_TICK + tickSpacing, "price too low");
        require(mid < TickMath.MAX_TICK - tickSpacing, "price too high");

        // Check TWAP deviation. This check prevents price manipulation before
        // the rebalance and also avoids rebalancing when price has just spiked.
        int56 twap = _getTwap(_pool);
        int56 deviation = mid > twap ? mid - twap : twap - mid;
        require(deviation <= maxTwapDeviation, "maxTwapDeviation");
    }

    // given the cumulative prices of the start and end of a period, and the length of the period, compute the average
    // price in terms of how much amount out is received for the amount in
    function _getTwap(IUniswapV3Pool _pool) private view returns (int56 amountOut) {
      (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) =
        _pool.observe(secondsAgo);
      return (tickCumulatives[1] - tickCumulatives[0]) / SECONDS_GRANULARITY;
    }
}
