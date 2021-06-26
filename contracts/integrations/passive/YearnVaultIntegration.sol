/*
    Copyright 2021 Babylon Finance

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
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';

import {IBabController} from '../../interfaces/IBabController.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {PassiveIntegration} from './PassiveIntegration.sol';
import {IYearnRegistry} from '../../interfaces/external/yearn/IYearnRegistry.sol';
import {IYearnVault} from '../../interfaces/external/yearn/IYearnVault.sol';

/**
 * @title YearnIntegration
 * @author Babylon Finance Protocol
 *
 * Yearn v2 Vault Integration
 */
contract YearnVaultIntegration is PassiveIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ State Variables ============ */

    IYearnRegistry private constant registry = IYearnRegistry(0xE15461B18EE31b7379019Dc523231C57d1Cbc18c);

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     * @param _weth                         Address of the WETH ERC20
     */
    constructor(IBabController _controller, address _weth) PassiveIntegration('yearnvaultsv2', _weth, _controller) {}

    /* ============ Internal Functions ============ */

    function _getSpender(address _asset) internal pure override returns (address) {
        return _asset;
    }

    function _getExpectedShares(address _asset, uint256 _amount) internal view override returns (uint256) {
        // Normalizing pricePerShare returned by Yearn
        return _amount.preciseDiv(IYearnVault(_asset).pricePerShare()).div(10**PreciseUnitMath.decimals().sub(ERC20(_asset).decimals()));
    }

    function _getPricePerShare(address _asset) internal view override returns (uint256) {
        return IYearnVault(_asset).pricePerShare();
    }

    function _getInvestmentAsset(address _asset) internal view override returns (address) {
        return IYearnVault(_asset).token();
    }

    /**
     * Return join investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * @param  _asset              Address of the vault
     * hparam  _investmentTokensOut            Amount of investment tokens to send
     * hparam  _tokenIn                        Addresses of tokens to send to the investment
     * @param  _maxAmountIn                    Amounts of tokens to send to the investment
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getEnterInvestmentCalldata(
        address, /* _strategy */
        address _asset,
        uint256, /* _investmentTokensOut */
        address, /* _tokenIn */
        uint256 _maxAmountIn
    )
        internal
        pure
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSelector(IYearnVault.deposit.selector, _maxAmountIn);

        return (_asset, 0, methodData);
    }

    /**
     * Return exit investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * @param  _asset              Address of the investment
     * @param  _investmentTokensIn             Amount of investment tokens to receive
     * hparam  _tokenOut                       Addresses of tokens to receive
     * hparam  _minAmountOut                   Amounts of investment tokens to receive
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getExitInvestmentCalldata(
        address, /* _strategy */
        address _asset,
        uint256 _investmentTokensIn,
        address, /* _tokenOut */
        uint256 /* _minAmountOut */
    )
        internal
        pure
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSelector(IYearnVault.withdraw.selector, _investmentTokensIn);

        return (_asset, 0, methodData);
    }
}
