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
pragma abicoder v2;

import 'hardhat/console.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {ISynthetix} from '../../interfaces/external/synthetix/ISynthetix.sol';
import {ISnxProxy} from '../../interfaces/external/synthetix/ISnxProxy.sol';
import {ISnxSynth} from '../../interfaces/external/synthetix/ISnxSynth.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';

import {TradeIntegration} from './TradeIntegration.sol';

/**
 * @title SynthetixTradeIntegration
 * @author Babylon Finance Protocol
 *
 * Synthethix trade integration
 */
contract SynthetixTradeIntegration is TradeIntegration {
    using SafeMath for uint256;

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    address internal constant SNX = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;

    /* ============ Constants ============ */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) TradeIntegration('synthetix_trade', _controller) {}

    /* ============ Internal Functions ============ */

    /**
     * Executes the trade through synthetix.
     *
     * @param _strategy             Address of the strategy
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of reserve asset token sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     */
    function _getTradeCallData(
        address _strategy,
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
        ISynthetix synthetix = ISynthetix(ISnxProxy(SNX).target());
        address sendTokenImpl = ISnxProxy(_sendToken).target();
        address receiveTokenImpl = ISnxProxy(_receiveToken).target();
        bytes memory methodData =
            abi.encodeWithSignature(
                'exchange(bytes32,uint256,bytes32)',
                ISnxSynth(sendTokenImpl).currencyKey(),
                _sendQuantity,
                ISnxSynth(receiveTokenImpl).currencyKey()
            );
        return (address(synthetix), 0, methodData);
    }

    /**
     * Returns the address to approve source tokens to for trading. This is the TokenTaker address
     *
     * @param _swapTarget          Address of the contract that will execute the swap
     * @return address             Address of the contract to approve tokens to
     */
    function _getSpender(address _swapTarget) internal view override returns (address) {
        return ISnxProxy(SNX).target();
    }

    /**
     * Checks liquidity of the trade
     *
     * @param _tradeInfo            Struct containing trade information used in internal functions
     * @param _sendQuantity         Units of token in SetToken sent to the exchange
     */
    function _checkLiquidity(TradeInfo memory _tradeInfo, uint256 _sendQuantity) internal view override returns (bool) {
        address reserveAsset = _tradeInfo.garden.reserveAsset();
        uint256 minLiquidityReserveAsset = _tradeInfo.garden.minLiquidityAsset();
        // TODO: Check
        return true;
    }

    /* ============ Private Functions ============ */
}
