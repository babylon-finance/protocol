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
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {IPoolIntegration} from '../../interfaces/IPoolIntegration.sol';

import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';

import {Operation} from './Operation.sol';

/**
 * @title AddLiquidityOperation
 * @author Babylon Finance
 *
 * Executes an add liquidity operation
 */
contract AddLiquidityOperation is Operation {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;
    using BytesLib for bytes;

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
        bytes calldata _data,
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
     * @param _data               OpData e.g. Address of the pool to enter
     * @param _garden             Garden of the strategy
     * @param _integration        Address of the integration to execute
     */
    function executeOperation(
        address _asset,
        uint256 _capital,
        uint8, /* _assetStatus */
        bytes calldata _data,
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
        address[] memory poolTokens = IPoolIntegration(_integration).getPoolTokens(_data);
        uint256[] memory _poolWeights = IPoolIntegration(_integration).getPoolWeights(_data);
        // Get the tokens needed to enter the pool
        uint256[] memory maxAmountsIn = _maxAmountsIn(_asset, _capital, _garden, _poolWeights, poolTokens);
        uint256 poolTokensOut = IPoolIntegration(_integration).getPoolTokensOut(_data, poolTokens[0], maxAmountsIn[0]);
        IPoolIntegration(_integration).joinPool(
            msg.sender,
            _data,
            poolTokensOut.sub(poolTokensOut.preciseMul(SLIPPAGE_ALLOWED)),
            poolTokens,
            maxAmountsIn
        );
        return (
            BytesLib.decodeOpDataAddress(_data),
            IERC20(BytesLib.decodeOpDataAddress(_data)).balanceOf(msg.sender),
            0
        ); // liquid
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
        bytes calldata _data,
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
        address pool = BytesLib.decodeOpDataAddress(_data);
        address[] memory poolTokens = IPoolIntegration(_integration).getPoolTokens(_data);
        uint256 lpTokens = IERC20(IPoolIntegration(_integration).getLPToken(_data)).balanceOf(msg.sender).preciseMul(_percentage); // Sell all pool tokens
        uint256[] memory _minAmountsOut = IPoolIntegration(_integration).getPoolMinAmountsOut(_data, lpTokens);
        IPoolIntegration(_integration).exitPool(
            msg.sender,
            _data,
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
        return (pool, 0, 0);
    }

    /**
     * Gets the NAV of the add liquidity op in the reserve asset
     *
     * @param _data               OpData e.g. PoolId or asset address
     * @param _garden             Garden the strategy belongs to
     * @param _integration        Status of the asset amount
     * @return _nav               NAV of the strategy
     */
    function getNAV(
        bytes calldata _data,
        IGarden _garden,
        address _integration
    ) external view override returns (uint256, bool) {
        address pool = BytesLib.decodeOpDataAddress(_data); // 64 bytes (w/o signature prefix bytes4)
        if (!IStrategy(msg.sender).isStrategyActive()) {
            return (0, true);
        }
        address[] memory poolTokens = IPoolIntegration(_integration).getPoolTokens(_data);
        uint256 NAV;
        address lpToken = IPoolIntegration(_integration).getLPToken(_data);
        uint256 totalSupply = IERC20(lpToken).totalSupply();
        uint256 lpTokens = IERC20(lpToken).balanceOf(msg.sender);
        for (uint256 i = 0; i < poolTokens.length; i++) {
            uint256 price = _getPrice(_garden.reserveAsset(), poolTokens[i] != address(0) ? poolTokens[i] : WETH);
            uint256 balance = poolTokens[i] != address(0) ? IERC20(poolTokens[i]).balanceOf(pool) : pool.balance;
            NAV += SafeDecimalMath.normalizeAmountTokens(
                poolTokens[i] != address(0) ? poolTokens[i] : WETH,
                _garden.reserveAsset(),
                balance.mul(lpTokens).div(totalSupply).preciseDiv(price)
            );
        }
        require(NAV != 0, 'NAV has to be bigger 0');
        return (NAV, true);
    }

    /* ============ Private Functions ============ */

    function _getMaxAmountTokenPool(
        address _asset,
        uint256 _capital,
        IGarden, /* _garden */
        uint256 _poolWeight,
        address _poolToken
    ) private returns (uint256) {
        uint256 normalizedAssetAmount = _capital.preciseMul(_poolWeight);
        uint256 price = _getPrice(_asset, _poolToken != address(0) ? _poolToken : WETH);
        uint256 normalizedTokenAmount =
            SafeDecimalMath.normalizeAmountTokens(_asset, _poolToken, normalizedAssetAmount.preciseMul(price));
        if (_poolToken != _asset && _poolToken != address(0)) {
            IStrategy(msg.sender).trade(_asset, normalizedAssetAmount, _poolToken);
            return IERC20(_poolToken).balanceOf(msg.sender);
        }
        if (_poolToken == address(0)) {
            if (_asset != WETH) {
                IStrategy(msg.sender).trade(_asset, normalizedAssetAmount, WETH); // normalized amount in original asset decimals
            }
            // Convert WETH to ETH
            // We consider the slippage in the trade
            normalizedTokenAmount = normalizedTokenAmount <= IERC20(WETH).balanceOf(msg.sender)
                ? normalizedTokenAmount
                : IERC20(WETH).balanceOf(msg.sender);
            IStrategy(msg.sender).handleWeth(false, normalizedTokenAmount); // normalized WETH/ETH amount with 18 decimals
        }
        return normalizedTokenAmount;
    }

    function _maxAmountsIn(
        address _asset,
        uint256 _capital,
        IGarden _garden,
        uint256[] memory _poolWeights,
        address[] memory poolTokens
    ) internal returns (uint256[] memory) {
        uint256[] memory maxAmountsIn = new uint256[](poolTokens.length);
        for (uint256 i = 0; i < poolTokens.length; i++) {
            maxAmountsIn[i] = _getMaxAmountTokenPool(_asset, _capital, _garden, _poolWeights[i], poolTokens[i]);
        }
        return maxAmountsIn;
    }
}
