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

import {IBabController} from '../../interfaces/IBabController.sol';

import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';

import {TradeIntegration} from './TradeIntegration.sol';

/**
 * @title UniswapV3TradeIntegration
 * @author Babylon Finance Protocol
 *
 * UniswapV3 trade integration
 */
contract UniswapV3TradeIntegration is TradeIntegration {
    using SafeMath for uint256;

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _weth                         Address of the WETH ERC20
     * @param _controller                   Address of the controller
     */
    constructor(
        IBabController _controller,
        address _weth
    ) TradeIntegration('univ3', _weth, _controller) {
    }

    /* ============ External Functions ============ */
    /**
     * Returns the conversion rate between the source token and the destination token
     * in 18 decimals, regardless of component token's decimals
     *
     * hparam  _sourceToken        Address of source token to be sold
     * hparam  _destinationToken   Address of destination token to buy
     * hparam  _sourceQuantity     Amount of source token to sell
     *
     * @return uint256             Conversion rate in wei
     * @return uint256             Slippage rate in wei
     */
    function getConversionRates(
        address,
        address,
        uint256
    ) external pure override returns (uint256, uint256) {
        revert('not implemented');
        return (0, 0);
    }

    /* ============ Internal Functions ============ */

    /**
     * Executes the trade through 1Inch.
     *
     * hparam _strategy             Address of the strategy
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of reserve asset token sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     */
    function _getTradeCallData(
        address, /*_strategy*/
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        return (address(0), 0, bytes(''));
    }

    /**
     * Returns the address to approve source tokens to for trading. This is the TokenTaker address
     *
     * @return address             Address of the contract to approve tokens to
     */
    function _getSpender() internal view override returns (address) {
        return address(0);
    }
}
