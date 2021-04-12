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
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Strategy} from './Strategy.sol';
import {IWETH} from '../interfaces/external/weth/IWETH.sol';
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
    using PreciseUnitMath for uint256;

    address public pool; // Pool to add liquidity to
    address[] public poolTokens; // List of pool tokens

    /**
     * Sets integration data for the pool strategy
     *
     * @param _pool                           Liquidity pool
     */
    function setData(address _pool) public onlyGardenAndNotSet {
        require(!dataSet, 'Data is set already');
        require(IPoolIntegration(integration).isPool(_pool), 'Not a valid pool');

        kind = 1;
        pool = _pool;
        poolTokens = IPoolIntegration(integration).getPoolTokens(pool);
        dataSet = true;
    }

    /**
     * Enters the pool strategy
     */
    function _enterStrategy(uint256 _capital) internal override {
        address reserveAsset = garden.reserveAsset();
        uint256[] memory _maxAmountsIn = new uint256[](poolTokens.length);
        uint256[] memory _poolWeights = IPoolIntegration(integration).getPoolWeights(pool);
        // Get the tokens needed to enter the pool
        uint256 ethValue = 0;
        for (uint256 i = 0; i < poolTokens.length; i++) {
            uint256 normalizedAmount = _capital.preciseMul(_poolWeights[i]);
            if (poolTokens[i] != reserveAsset && poolTokens[i] != address(0)) {
                _trade(reserveAsset, normalizedAmount, poolTokens[i]);
                _maxAmountsIn[i] = IERC20(poolTokens[i]).balanceOf(address(this));
            } else {
                if (poolTokens[i] == address(0)) {
                    if (reserveAsset != garden.weth()) {
                        _trade(reserveAsset, normalizedAmount, garden.weth());
                    }
                    // Convert WETH to ETH
                    IWETH(garden.weth()).withdraw(normalizedAmount);
                    ethValue = normalizedAmount;
                }
                _maxAmountsIn[i] = normalizedAmount;
            }
        }
        uint256 poolTokensOut = IPoolIntegration(integration).getPoolTokensOut(pool, poolTokens[0], _maxAmountsIn[0]);
        IPoolIntegration(integration).joinPool(
            pool,
            poolTokensOut.sub(poolTokensOut.preciseMul(SLIPPAGE_ALLOWED)),
            poolTokens,
            _maxAmountsIn
        );
    }

    /**
     * Exits the pool strategy.
     */
    function _exitStrategy() internal override {
        uint256 lpTokens = IERC20(pool).balanceOf(address(this)); // Sell all pool tokens
        uint256[] memory _minAmountsOut = IPoolIntegration(integration).getPoolMinAmountsOut(pool, lpTokens);
        IPoolIntegration(integration).exitPool(
            pool,
            lpTokens, // Sell all pool tokens
            poolTokens,
            _minAmountsOut
        );
        // Exit Pool tokens
        address reserveAsset = garden.reserveAsset();
        for (uint256 i = 0; i < poolTokens.length; i++) {
            if (poolTokens[i] != reserveAsset) {
                if (poolTokens[i] == address(0)) {
                    IWETH(garden.weth()).deposit{value: address(this).balance}();
                } else {
                    _trade(poolTokens[i], IERC20(poolTokens[i]).balanceOf(address(this)), reserveAsset);
                }
            }
        }
    }
}
