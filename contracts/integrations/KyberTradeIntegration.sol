/*
    Copyright 2020 Babylon Finance

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
import {TradeIntegration} from './TradeIntegration.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {IKyberNetworkProxy} from '../interfaces/external/kyber/IKyberNetworkProxy.sol';

/**
 * @title KyberTradeIntegration
 * @author Babylon Finance Protocol
 *
 * Kyber protocol trade integration
 */
contract KyberTradeIntegration is TradeIntegration {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;

    /* ============ State Variables ============ */

    // Address of Kyber Network Proxy
    address public kyberNetworkProxyAddress;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     * @param _weth                         Address of the WETH ERC20
     * @param _kyberNetworkProxyAddress    Address of Kyber Network Proxy contract
     */
    constructor(
        address _controller,
        address _weth,
        address _kyberNetworkProxyAddress
    ) TradeIntegration('kyber', _weth, _controller) {
        kyberNetworkProxyAddress = _kyberNetworkProxyAddress;
    }

    /* ============ External Functions ============ */

    /**
     * Returns the conversion rate between the source token and the destination token
     * in 18 decimals, regardless of component token's decimals
     *
     * @param  _sourceToken        Address of source token to be sold
     * @param  _destinationToken   Address of destination token to buy
     * @param  _sourceQuantity     Amount of source token to sell
     *
     * @return uint256             Conversion rate in wei
     * @return uint256             Slippage rate in wei
     */
    function getConversionRates(
        address _sourceToken,
        address _destinationToken,
        uint256 _sourceQuantity
    ) external view returns (uint256, uint256) {
        // Get Kyber expectedRate to trade with
        return
            IKyberNetworkProxy(kyberNetworkProxyAddress).getExpectedRate(
                _sourceToken,
                _destinationToken,
                _sourceQuantity
            );
    }

    /* ============ Internal Functions ============ */

    /**
     * Get calldata through Kyber.
     *
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of reserve asset token sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     * @param _minReceiveQuantity   Min units of wanted token to be received from the exchange
     */
    function _getTradeCallData(
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
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
        (, uint256 worstRate) =
            IKyberNetworkProxy(kyberNetworkProxyAddress).getExpectedRate(_sendToken, _receiveToken, _sendQuantity);

        console.log('execute kyber');
        // Encode method data for TradeIntegration to invoke
        bytes memory methodData =
            abi.encodeWithSignature(
                'trade(address,uint256,address,address,uint256,uint256,address)',
                _sendToken,
                _sendQuantity,
                _receiveToken,
                msg.sender,
                PreciseUnitMath.maxUint256(), // Sell entire amount of sourceToken
                worstRate, // Trade with implied conversion rate
                msg.sender // Garden address
            );

        return (kyberNetworkProxyAddress, 0, methodData);
    }

    /**
     * Returns the address to approve source tokens to for trading. This is the Kyber Network
     * Proxy address
     *
     * @return address             Address of the contract to approve tokens to
     */
    function _getSpender() internal view override returns (address) {
        return kyberNetworkProxyAddress;
    }
}
