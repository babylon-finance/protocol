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

pragma solidity 0.7.6;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {Operation} from './Operation.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {IWETH} from '../../interfaces/external/weth/IWETH.sol';
import {IPoolIntegration} from '../../interfaces/IPoolIntegration.sol';

/**
 * @title AddLiquidityOperation
 * @author Babylon Finance
 *
 * Executes a add liquidity operation
 */
contract AddLiquidityOperation is Operation {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, address _controller) Operation(_name, _controller) {
    }

    /**
     * Sets operation data for the add liquidity operation
     *
     * @param _data                   Operation data
     */
    function validateOperation(
        bytes calldata _data,
        IGarden _garden,
        IStrategy _strategy,
        address _integration
    ) external view override onlyStrategy {
        require(IPoolIntegration(_integration).isPool(_parseData(_data)), 'Not a valid pool');
    }

    /**
     * Executes the add liquidity operation
     * @param _capital      Amount of capital received from the garden
     */
    function executeOperation(
        address _asset,
        uint256 _capital,
        bytes calldata _data,
        IGarden _garden,
        IStrategy _strategy,
        address _integration
    ) external override onlyStrategy returns (address, uint256) {
        address pool = _parseData(_data);
        address[] memory poolTokens = IPoolIntegration(_integration).getPoolTokens(pool);
        uint256[] memory _maxAmountsIn = new uint256[](poolTokens.length);
        uint256[] memory _poolWeights = IPoolIntegration(_integration).getPoolWeights(pool);
        // Get the tokens needed to enter the pool
        uint256 ethValue = 0;
        for (uint256 i = 0; i < poolTokens.length; i++) {
            uint256 normalizedAmount = _capital.preciseMul(_poolWeights[i]);
            if (poolTokens[i] != _asset && poolTokens[i] != address(0)) {
                IStrategy(_strategy).trade(_asset, normalizedAmount, poolTokens[i]);
                _maxAmountsIn[i] = IERC20(poolTokens[i]).balanceOf(msg.sender);
            } else {
                if (poolTokens[i] == address(0)) {
                    if (_asset != _garden.WETH()) {
                        IStrategy(_strategy).trade(_asset, normalizedAmount, _garden.WETH());
                    }
                    // Convert WETH to ETH
                    IWETH(_garden.WETH()).withdraw(normalizedAmount);
                    ethValue = normalizedAmount;
                }
                _maxAmountsIn[i] = normalizedAmount;
            }
        }
        uint256 poolTokensOut = IPoolIntegration(_integration).getPoolTokensOut(pool, poolTokens[0], _maxAmountsIn[0]);
        IPoolIntegration(_integration).joinPool(
            pool,
            poolTokensOut.sub(poolTokensOut.preciseMul(SLIPPAGE_ALLOWED)),
            poolTokens,
            _maxAmountsIn
        );
        return (pool, IERC20(pool).balanceOf(msg.sender));
    }

    /**
     * Exits the add liquidity operation.
     * @param _percentage of capital to exit from the strategy
     */
    function exitOperation(
        uint256 _percentage,
        bytes calldata _data,
        IGarden _garden,
        IStrategy _strategy,
        address _integration
    ) external override onlyStrategy {
        require(_percentage <= 100e18, 'Unwind Percentage <= 100%');
        address pool = _parseData(_data);
        address[] memory poolTokens = IPoolIntegration(_integration).getPoolTokens(pool);
        uint256 lpTokens = IERC20(pool).balanceOf(msg.sender).preciseMul(_percentage); // Sell all pool tokens
        uint256[] memory _minAmountsOut = IPoolIntegration(_integration).getPoolMinAmountsOut(pool, lpTokens);
        IPoolIntegration(_integration).exitPool(
            pool,
            lpTokens, // Sell all pool tokens
            poolTokens,
            _minAmountsOut
        );
        // Exit Pool tokens
        address reserveAsset = _garden.reserveAsset();
        for (uint256 i = 0; i < poolTokens.length; i++) {
            if (poolTokens[i] != reserveAsset) {
                if (poolTokens[i] == address(0)) {
                    IWETH(_garden.WETH()).deposit{value: address(msg.sender).balance}();
                } else {
                    IStrategy(_strategy).trade(
                        poolTokens[i],
                        IERC20(poolTokens[i]).balanceOf(msg.sender),
                        reserveAsset
                    );
                }
            }
        }
    }

    /**
     * Gets the NAV of the add liquidity op in the reserve asset
     *
     * @return _nav           NAV of the strategy
     */
    function getNAV(
        bytes calldata _data,
        IGarden _garden,
        IStrategy _strategy,
        address _integration
    ) external view override onlyStrategy returns (uint256) {
        if (!_strategy.isStrategyActive()) {
            return 0;
        }
        address pool = _parseData(_data);
        address[] memory poolTokens = IPoolIntegration(_integration).getPoolTokens(pool);
        uint256 NAV;
        uint256 totalSupply = IERC20(pool).totalSupply();
        uint256 lpTokens = IERC20(pool).balanceOf(address(this));
        for (uint256 i = 0; i < poolTokens.length; i++) {
            uint256 price =
                _getPrice(_garden.reserveAsset(), poolTokens[i] != address(0) ? poolTokens[i] : _garden.WETH());
            uint256 balance = poolTokens[i] != address(0) ? IERC20(poolTokens[i]).balanceOf(pool) : pool.balance;
            NAV += balance.mul(lpTokens).div(totalSupply).preciseDiv(price);
        }
        require(NAV != 0, 'NAV has to be bigger 0');
        return NAV;
    }

    /* ============ Private Functions ============ */

    function _parseData(bytes calldata _data) private view returns (address) {
        return address(0);
    }
}
