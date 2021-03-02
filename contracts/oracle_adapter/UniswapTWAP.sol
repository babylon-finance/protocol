/*
    Copyright 2020 Babylon Finance

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

pragma solidity 0.7.4;

import "hardhat/console.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol';
import '@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';
import { PreciseUnitMath } from "../lib/PreciseUnitMath.sol";
import { IBabController } from "../interfaces/IBabController.sol";

/**
 * @title UniswapTWAP
 * @author Babylon Finance Protocol
 *
 * Sliding window oracle that uses observations collected over a window to provide moving price averages in the past
 * `windowSize` with a precision of `windowSize / granularity`
 * note this is a singleton oracle and only needs to be deployed once per desired parameters, which
 * differs from the simple oracle which must be deployed once per pair.
 */
contract UniswapTWAP is Ownable {
    using FixedPoint for *;
    using SafeMath for uint;
    using PreciseUnitMath for uint256;

    struct Observation {
        uint timestamp;
        uint price0Cumulative;
        uint price1Cumulative;
    }

    /* ============ State Variables ============ */

    // Instance of the Controller contract
    IBabController public controller;

    // Address of Uniswap factory
    address public immutable factory;
    // the desired amount of time over which the moving average should be computed, e.g. 24 hours
    uint public immutable windowSize;
    // the number of observations stored for each pair, i.e. how many price observations are stored for the window.
    // as granularity increases from 1, more frequent updates are needed, but moving averages become more precise.
    // averages are computed over intervals with sizes in the range:
    //   [windowSize - (windowSize / granularity) * 2, windowSize]
    // e.g. if the window size is 24 hours, and the granularity is 24, the oracle will return the average price for
    //   the period:
    //   [now - [22 hours, 24 hours], now]
    uint8 public immutable granularity;
    // this is redundant with granularity and windowSize, but stored for gas savings & informational purposes.
    uint public immutable periodSize;

    // mapping from pair address to a list of price observations of that pair
    mapping(address => Observation[]) public pairObservations;


    /* ============ Constructor ============ */

    /**
     * Set state variables
     *
     * @param _controller         Instance of controller contract
     * @param _factory            Address of Uniswap factory
     * @param _windowSize         Array of allowed Uniswap pools
     * @param _granularity        Array of allowed Uniswap pools
     */
    constructor(address _controller, address _factory, uint _windowSize, uint8 _granularity) {
      require(_granularity > 1, 'SlidingWindowOracle: GRANULARITY');
      require(
        (periodSize = _windowSize / _granularity) * _granularity == _windowSize,
        'SlidingWindowOracle: WINDOW_NOT_EVENLY_DIVISIBLE'
      );
      factory = _factory;
      controller = IBabController(_controller);
      windowSize = _windowSize;
      granularity = _granularity;
    }

    /* ============ External Functions ============ */

    // returns the index of the observation corresponding to the given timestamp
    function observationIndexOf(uint timestamp) public view returns (uint8 index) {
      uint epochPeriod = timestamp / periodSize;
      return uint8(epochPeriod % granularity);
    }

    // update the cumulative price for the observation at the current timestamp. each observation is updated at most
    // once per epoch period.
    function update(address tokenA, address tokenB) external {
      address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);

      // populate the array with empty observations (first call only)
      for (uint i = pairObservations[pair].length; i < granularity; i++) {
        pairObservations[pair].push();
      }
      // get the observation for the current period
      uint8 observationIndex = observationIndexOf(block.timestamp);
      Observation storage observation = pairObservations[pair][observationIndex];

      // we only want to commit updates once per period (i.e. windowSize / granularity)
      uint timeElapsed = block.timestamp - observation.timestamp;
      if (timeElapsed > periodSize) {
        (uint price0Cumulative, uint price1Cumulative,) = UniswapV2OracleLibrary.currentCumulativePrices(pair);
        observation.timestamp = block.timestamp;
        observation.price0Cumulative = price0Cumulative;
        observation.price1Cumulative = price1Cumulative;
      }
    }

    // returns the amount out corresponding to the amount in for a given token using the moving average over the time
    // range [now - [windowSize, windowSize - periodSize * 2], now]
    // update must have been called for the bucket corresponding to timestamp `now - windowSize`
    function getPrice(address tokenIn, address tokenOut) external view returns (uint amountOut) {
      address pair = UniswapV2Library.pairFor(factory, tokenIn, tokenOut);
      Observation storage firstObservation = getFirstObservationInWindow(pair);

      uint timeElapsed = block.timestamp - firstObservation.timestamp;
      require(timeElapsed <= windowSize, 'SlidingWindowOracle: MISSING_HISTORICAL_OBSERVATION');
      // should never happen.
      require(timeElapsed >= windowSize - periodSize * 2, 'SlidingWindowOracle: UNEXPECTED_TIME_ELAPSED');

      (uint price0Cumulative, uint price1Cumulative,) = UniswapV2OracleLibrary.currentCumulativePrices(pair);
      (address token0,) = UniswapV2Library.sortTokens(tokenIn, tokenOut);

      if (token0 == tokenIn) {
        return computeAmountOut(firstObservation.price0Cumulative, price0Cumulative, timeElapsed);
      } else {
        return computeAmountOut(firstObservation.price1Cumulative, price1Cumulative, timeElapsed);
      }
    }

    /* ============ Internal Functions ============ */

    // given the cumulative prices of the start and end of a period, and the length of the period, compute the average
    // price in terms of how much amount out is received for the amount in
    function computeAmountOut(
        uint priceCumulativeStart, uint priceCumulativeEnd,
        uint timeElapsed
    ) private pure returns (uint amountOut) {
      // overflow is desired.
      FixedPoint.uq112x112 memory priceAverage = FixedPoint.uq112x112(
        uint224((priceCumulativeEnd - priceCumulativeStart) / timeElapsed)
      );
      amountOut = priceAverage.mul(1).decode144();
      amountOut = amountOut.preciseDiv(1);
    }

    // returns the observation from the oldest epoch (at the beginning of the window) relative to the current time
    function getFirstObservationInWindow(address pair) private view returns (Observation storage firstObservation) {
      uint8 observationIndex = observationIndexOf(block.timestamp);
      // no overflow issue. if observationIndex + 1 overflows, result is still zero.
      uint8 firstObservationIndex = (observationIndex + 1) % granularity;
      firstObservation = pairObservations[pair][firstObservationIndex];
    }
}
