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
    constructor(string memory _name, address _controller) Operation(_name, _controller) {}

    /**
     * Sets operation data for the add liquidity operation
     *
     * @param _data                   Operation data
     */
    function validateOperation(
        address _data,
        IGarden, /* _garden */
        address _integration,
        uint256 /* _index */
    ) external view override onlyStrategy {
        require(IPoolIntegration(_integration).isPool(_data), 'Not a valid pool');
    }

    /**
     * Executes the add liquidity operation
     * @param _asset              Asset to receive into this operation
     * @param _capital            Amount of asset received
     * param _assetStatus        Status of the asset amount
     * @param _pool               Address of the pool to enter
     * @param _garden             Garden of the strategy
     * @param _integration        Address of the integration to execute
     */
    function executeOperation(
        address _asset,
        uint256 _capital,
        uint8, /* _assetStatus */
        address _pool,
        IGarden _garden,
        address _integration
    )
        external
        override
        onlyStrategy
        returns (
            address,
            uint256,
            uint8
        )
    {
        address[] memory poolTokens = IPoolIntegration(_integration).getPoolTokens(_pool);
        uint256[] memory _maxAmountsIn = new uint256[](poolTokens.length);
        uint256[] memory _poolWeights = IPoolIntegration(_integration).getPoolWeights(_pool);
        // Get the tokens needed to enter the pool
        for (uint256 i = 0; i < poolTokens.length; i++) {
            _maxAmountsIn[i] = _getMaxAmountTokenPool(_asset, _capital, _garden, _poolWeights[i], poolTokens[i]);
        }
        uint256 poolTokensOut = IPoolIntegration(_integration).getPoolTokensOut(_pool, poolTokens[0], _maxAmountsIn[0]);
        IPoolIntegration(_integration).joinPool(
            msg.sender,
            _pool,
            poolTokensOut.sub(poolTokensOut.preciseMul(SLIPPAGE_ALLOWED)),
            poolTokens,
            _maxAmountsIn
        );
        return (_pool, IERC20(_pool).balanceOf(msg.sender), 0); // liquid
    }

    /**
     * Exits the add liquidity operation.
     * @param _percentage of capital to exit from the strategy
     */
    function exitOperation(
        address, /* _asset */
        uint256, /* _remaining */
        uint8, /* _assetStatus */
        uint256 _percentage,
        address _data,
        IGarden _garden,
        address _integration
    )
        external
        override
        onlyStrategy
        returns (
            address,
            uint256,
            uint8
        )
    {
        require(_percentage <= 100e18, 'Unwind Percentage <= 100%');
        address pool = _data;
        address[] memory poolTokens = IPoolIntegration(_integration).getPoolTokens(pool);
        uint256 lpTokens = IERC20(pool).balanceOf(msg.sender).preciseMul(_percentage); // Sell all pool tokens
        uint256[] memory _minAmountsOut = IPoolIntegration(_integration).getPoolMinAmountsOut(pool, lpTokens);
        IPoolIntegration(_integration).exitPool(
            msg.sender,
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
                    IStrategy(msg.sender).handleWeth(true, address(msg.sender).balance);
                    poolTokens[i] = WETH;
                }
                if (poolTokens[i] != reserveAsset) {
                    IStrategy(msg.sender).trade(
                        poolTokens[i],
                        IERC20(poolTokens[i]).balanceOf(msg.sender),
                        reserveAsset
                    );
                }
            }
        }
        return (_data, 0, 0);
    }

    /**
     * Gets the NAV of the add liquidity op in the reserve asset
     *
     * @param _data         Pool
     * @param _garden             Garden the strategy belongs to
     * @param _integration        Status of the asset amount
     * @return _nav               NAV of the strategy
     */
    function getNAV(
        address _data,
        IGarden _garden,
        address _integration
    ) external view override returns (uint256) {
        if (!IStrategy(msg.sender).isStrategyActive()) {
            return 0;
        }
        address pool = _data;
        address[] memory poolTokens = IPoolIntegration(_integration).getPoolTokens(pool);
        uint256 NAV;
        uint256 totalSupply = IERC20(pool).totalSupply();
        uint256 lpTokens = IERC20(pool).balanceOf(msg.sender);
        for (uint256 i = 0; i < poolTokens.length; i++) {
            uint256 price = _getPrice(_garden.reserveAsset(), poolTokens[i] != address(0) ? poolTokens[i] : WETH);
            uint256 balance = poolTokens[i] != address(0) ? IERC20(poolTokens[i]).balanceOf(pool) : pool.balance;
            NAV += balance.mul(lpTokens).div(totalSupply).preciseDiv(price);
        }
        require(NAV != 0, 'NAV has to be bigger 0');
        return NAV;
    }

    /* ============ Private Functions ============ */

    function _getMaxAmountTokenPool(
        address _asset,
        uint256 _capital,
        IGarden, /* _garden */
        uint256 _poolWeight,
        address _poolToken
    ) private returns (uint256) {
        uint256 normalizedAmount = _capital.preciseMul(_poolWeight);
        if (_poolToken != _asset && _poolToken != address(0)) {
            IStrategy(msg.sender).trade(_asset, normalizedAmount, _poolToken);
            return IERC20(_poolToken).balanceOf(msg.sender);
        }
        if (_poolToken == address(0)) {
            if (_asset != WETH) {
                IStrategy(msg.sender).trade(_asset, normalizedAmount, WETH);
            }
            // Convert WETH to ETH
            IStrategy(msg.sender).handleWeth(false, normalizedAmount);
        }
        return normalizedAmount;
    }
}
