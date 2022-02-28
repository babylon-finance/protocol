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
import {TradeIntegration} from './TradeIntegration.sol';
import {IPaladinZap} from '../../interfaces/external/paladin/IPaladinZap.sol';

/**
 * @title PaladinTradeIntegration
 * @author Babylon Finance Protocol
 *
 * PaladinTradeIntegration
 */
contract PaladinTradeIntegration is TradeIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ State Variables ============ */

    IERC20 private constant aave = IERC20(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);
    IERC20 private constant stkAave = IERC20(0x4da27a545c0c5B758a6BA100e3a049001de870f5);

    IPaladinZap private constant paladinZap = IPaladinZap(0xe0fb13edC73FE156A636bc532FC2e56F9d54AA62);

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) TradeIntegration('paladin_trade', _controller) {}

    /* ============ Internal Functions ============ */

    /**
     * Returns the address to approve source tokens to for trading. This is the TokenTaker address
     *
     * @return address             Address of the contract to approve tokens to
     */
    function _getSpender(
        address /* _asset */
    ) internal pure override returns (address) {
        return address(paladinZap);
    }

    /**
     * Executes the trade through paladin.
     *
     * hparam _strategy             Address of the strategy
     * @param _sendToken            Address of the token to be sent to the heart
     * @param _sendQuantity         Units of reserve asset token sent to the heart
     * hparam _receiveToken         Address of the token that will be received from the heart
     */
    function _getTradeCallData(
        address, /* _strategy */
        address _sendToken,
        uint256 _sendQuantity,
        address /* _receiveToken */
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
                _sendQuantity,
                0xDef1C0ded9bec7F1a1670819833240f027b25EfF,
                address(0),
                bytes('')
            );
        return (address(paladinZap), 0, methodData);
    }
}
