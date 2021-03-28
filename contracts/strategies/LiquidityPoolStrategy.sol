/*
    Copyright 2021 Babylon Finance.

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

import 'hardhat/console.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Strategy} from './Strategy.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IPoolIntegration} from '../interfaces/IPoolIntegration.sol';

/**
 * @title LongStrategy
 * @author Babylon Finance
 *
 * Holds the data for a strategy that adds liquidity to a pool
 */
contract LiquidityPoolStrategy is Strategy {
    using SafeMath for uint256;

    address public pool; // Pool to add liquidity to
    uint256 public minReceiveQuantity; // Min amount of pool tokens to receive
    address[] public poolTokens; // List of pool tokens

    /**
     * Sets integration data for the pool strategy
     *
     * @param _pool                           Liquidity pool
     * @param _minReceiveQuantity             Min amount of pool tokens to get
     */
    function setPoolData(address _pool, uint256 _minReceiveQuantity) public onlyIdeator {
        kind = 1;
        require(_minReceiveQuantity > 0, 'Must receive assets back');
        require(IPoolIntegration(integration).isPool(pool), 'Must be a valid pool of this protocol');
        pool = _pool;
        minReceiveQuantity = _minReceiveQuantity;
        poolTokens = IPoolIntegration(integration).getPoolTokens(pool);
    }

    /**
     * Enters the pool strategy
     */
    function _enterStrategy(uint256 _capital) internal override {
        address reserveAsset = garden.getReserveAsset();
        uint256[] memory _maxAmountsIn = new uint256[](poolTokens.length);
        // Get the tokens needed to enter the pool
        for (uint256 i = 0; i < poolTokens.length; i++) {
            if (poolTokens[i] != reserveAsset) {
                // TODO: fix for pools that are not equally weighted
                _trade(reserveAsset, _capital.div(poolTokens.length), poolTokens[i]);
                _maxAmountsIn[i] = IERC20(poolTokens[i]).balanceOf(address(this));
            }
        }
        IPoolIntegration(integration).joinPool(pool, minReceiveQuantity, poolTokens, _maxAmountsIn);
    }

    /**
     * Exits the pool strategy.
     */
    function _exitStrategy() internal override {
        uint256[] memory _minAmountsOut = new uint256[](poolTokens.length);
        IPoolIntegration(integration).exitPool(
            pool,
            IERC20(pool).balanceOf(address(this)), // Sell all pool tokens
            poolTokens,
            _minAmountsOut
        );
        // Exit Pool tokens
        address reserveAsset = garden.getReserveAsset();
        for (uint256 i = 0; i < positions.length; i++) {
            if (poolTokens[i] != reserveAsset) {
                _trade(poolTokens[i], IERC20(poolTokens[i]).balanceOf(address(this)), reserveAsset);
            }
        }
    }
}
