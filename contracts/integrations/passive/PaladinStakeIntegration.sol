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

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';

import {IBabController} from '../../interfaces/IBabController.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {PassiveIntegration} from './PassiveIntegration.sol';
import {IPaladinZap} from '../../interfaces/external/paladin/IPaladinZap.sol';

/**
 * @title PaladinStakeIntegration
 * @author Babylon Finance Protocol
 *
 * Lido Integration
 */
contract PaladinStakeIntegration is PassiveIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ State Variables ============ */

    IERC20 private constant aave = IERC20(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);
    IERC20 private constant stkAave = IERC20(0x4da27a545c0c5B758a6BA100e3a049001de870f5);
    IERC20 private constant palStkAAVE = IERC20(0x24E79e946dEa5482212c38aaB2D0782F04cdB0E0);

    IPaladinZap private constant paladinZap = IPaladinZap(0xe0fb13edC73FE156A636bc532FC2e56F9d54AA62);

    address private constant curvePalStkAave = 0x48536EC5233297C367fd0b6979B75d9270bB6B15;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) PassiveIntegration('paladinstaking', _controller) {}

    /* ============ Internal Functions ============ */

    function _getSpender(
        address, /* _asset */
        uint8 _op
    ) internal pure override returns (address) {
        if (_op == 0) {
            return address(paladinZap);
        }
        return address(curvePalStkAave);
    }

    function _getExpectedShares(
        address, /* _asset */
        uint256 /* _amount */
    ) internal pure override returns (uint256) {
        return 1e18;
    }

    function _getPricePerShare(
        address /* _asset */
    ) internal pure override returns (uint256) {
        // Will fetch it from price oracle
        return 1e18;
    }

    function _getInvestmentAsset(
        address /* _asset */
    ) internal pure override returns (address) {
        return address(aave);
    }

    /**
     * Return join investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * hparam  _asset                          Address of the vault
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
        address, /* _asset */
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
        // Encode method data for Strategy to invoke
        bytes memory methodData =
            abi.encodeWithSignature(
                'zapDeposit(address,address,address,uint256,address,address,bytes)',
                aave,
                stkAave,
                0xCDc3DD86C99b58749de0F697dfc1ABE4bE22216d,
                _maxAmountIn,
                0xDef1C0ded9bec7F1a1670819833240f027b25EfF,
                address(0),
                bytes('')
            );
        return (address(paladinZap), 0, methodData);
    }

    /**
     * Return exit investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * hparam  _asset                          Address of the investment
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
        address, /* _asset */
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
        // Encode method data for Strategy to invoke
        bytes memory methodData =
            abi.encodeWithSignature(
                'exchange(uint256,uint256,uint256,uint256)',
                1,
                0,
                _investmentTokensIn,
                _investmentTokensIn.preciseMul(96e16)
            );
        // Need to swap via curve.
        return (curvePalStkAave, 0, methodData);
    }
}
