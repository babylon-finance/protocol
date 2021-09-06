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
        address[] memory poolTokens = IPoolIntegration(_integration).getPoolTokens(_data, false);
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
            _getLPTokenFromBytes(_integration, _data),
            IERC20(_getLPTokenFromBytes(_integration, _data)).balanceOf(msg.sender),
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
        address[] memory poolTokens = IPoolIntegration(_integration).getPoolTokens(_data, false);
        uint256 lpTokens =
            IERC20(IPoolIntegration(_integration).getLPToken(pool)).balanceOf(msg.sender).preciseMul(_percentage); // Sell all pool tokens
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
                if (_isETH(poolTokens[i])) {
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
        _sellRewardTokens(_integration, _data, reserveAsset);
        return (reserveAsset, IERC20(reserveAsset).balanceOf(msg.sender), 0);
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
        if (!IStrategy(msg.sender).isStrategyActive()) {
            return (0, true);
        }
        address pool = BytesLib.decodeOpDataAddress(_data); // 64 bytes (w/o signature prefix bytes4)
        pool = IPoolIntegration(_integration).getPool(pool);
        uint256 price = 0;
        IERC20 lpToken = IERC20(IPoolIntegration(_integration).getLPToken(pool));
        // // Price lp token directly if possible
        // uint256 price = _getPrice(address(lpToken), _garden.reserveAsset());
        // console.log('lp token price', price, lpToken.balanceOf(msg.sender));
        // if (price != 0) {
        //     return (
        //         SafeDecimalMath.normalizeAmountTokens(
        //             address(lpToken),
        //             _garden.reserveAsset(),
        //             lpToken.balanceOf(msg.sender).preciseMul(price)
        //         ),
        //         true
        //     );
        // }
        uint256 NAV;
        address[] memory poolTokens = IPoolIntegration(_integration).getPoolTokens(_data, true);
        for (uint256 i = 0; i < poolTokens.length; i++) {
            address asset = _isETH(poolTokens[i]) ? WETH : poolTokens[i];
            price = _getPrice(_garden.reserveAsset(), asset);
            // If the actual token doesn't have a price, use underlying as approx
            if (price == 0) {
                uint256 rate;
                (asset, rate) = IPoolIntegration(_integration).getUnderlyingAndRate(_data, i);
                if (rate != 0) {
                    price = _getPrice(_garden.reserveAsset(), asset);
                    price = price.preciseDiv(rate);
                }
            }
            uint256 balance = !_isETH(poolTokens[i]) ? IERC20(poolTokens[i]).balanceOf(pool) : pool.balance;
            if (price != 0 && balance != 0) {
                NAV += SafeDecimalMath.normalizeAmountTokens(
                    asset,
                    _garden.reserveAsset(),
                    balance.mul(lpToken.balanceOf(msg.sender)).div(lpToken.totalSupply()).preciseDiv(price)
                );
            }
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
        uint256 price = _getPrice(_asset, _isETH(_poolToken) ? WETH : _poolToken);
        uint256 normalizedTokenAmount =
            SafeDecimalMath.normalizeAmountTokens(_asset, _poolToken, normalizedAssetAmount.preciseMul(price));
        if (_poolToken != _asset && !_isETH(_poolToken)) {
            IStrategy(msg.sender).trade(_asset, normalizedAssetAmount, _poolToken);
            return IERC20(_poolToken).balanceOf(msg.sender);
        }
        if (_isETH(_poolToken)) {
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

    function _getLPTokenFromBytes(address _integration, bytes calldata _data) internal view returns (address) {
        return IPoolIntegration(_integration).getLPToken(BytesLib.decodeOpDataAddress(_data));
    }

    function _isETH(address _address) internal pure returns (bool) {
        return _address == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE || _address == address(0);
    }

    /**
     * Sells the reward tokens obtained.
     * @param _integration                    Address of the integration
     * @param _data                           Calldata
     * @param _reserveAsset                   Reserve Asset
     */
    function _sellRewardTokens(
        address _integration,
        bytes calldata _data,
        address _reserveAsset
    ) internal {
        address[] memory rewards = IPoolIntegration(_integration).getRewardTokens(_data);
        for (uint256 i = 0; i < rewards.length; i++) {
            if (rewards[i] != address(0)) {
                try
                    IStrategy(msg.sender).trade(rewards[i], IERC20(rewards[i]).balanceOf(msg.sender), _reserveAsset)
                {} catch {}
            }
        }
    }
}
