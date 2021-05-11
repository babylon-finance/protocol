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

import {IBabController} from '../interfaces/IBabController.sol';
import {IOracleAdapter} from '../interfaces/IOracleAdapter.sol';

/**
 * @title UniswapTWAPV3
 * @author Babylon Finance Protocol
 *
 * Uses uniswap V3 to get the price of a token pair
 */
contract UniswapTWAPV3 is Ownable, IOracleAdapter {
    /* ============ State Variables ============ */

    // Instance of the Controller contract
    IBabController public controller;

    // Name to identify this adapter
    string public constant name = 'uniswapTwapV3';

    // Address of Uniswap factory
    IUniswapV3Factory public immutable factory;

    // the desired seconds agos array passed to the observe method
    uint32[] public secondsAgo = new uint32[](2);
    uint32 public constant SECONDS_GRANULARITY = 900;

    uint24 private constant FEE_LOW = 500;
    uint24 private constant FEE_MEDIUM = 3000;
    uint24 private constant FEE_HIGH = 10000;

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
        IUniswapV3Pool pairLow = IUniswapV3Pool(factory.getPool(tokenIn, tokenOut, FEE_LOW));
        IUniswapV3Pool pairMedium = IUniswapV3Pool(factory.getPool(tokenIn, tokenOut, FEE_MEDIUM));
        IUniswapV3Pool pairHigh = IUniswapV3Pool(factory.getPool(tokenIn, tokenOut, FEE_HIGH));

        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) =
            pairLow.observe(secondsAgo);
        return (true, computeAmountOut(tickCumulatives));
    }

    function update(address tokenA, address tokenB) external override {}

    /* ============ Internal Functions ============ */

    // given the cumulative prices of the start and end of a period, and the length of the period, compute the average
    // price in terms of how much amount out is received for the amount in
    function computeAmountOut(int56[] memory tickCumulatives) private pure returns (uint256 amountOut) {
        uint32 ticksDiff = uint32(tickCumulatives[1] - tickCumulatives[0]) / SECONDS_GRANULARITY;
        if (tickCumulatives[1] >= tickCumulatives[0]) {
          return 10001e18 ** (uint256(ticksDiff));
        } else {
          return 10001e18 / (10001e18 ** uint256(-ticksDiff));
        }
    }
}
