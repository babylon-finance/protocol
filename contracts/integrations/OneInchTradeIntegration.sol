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
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {IOneInchExchange} from '../interfaces/external/1inch/IOneInchExchange.sol';
import {TradeIntegration} from './TradeIntegration.sol';

/**
 * @title 1InchTradeIntegration
 * @author Babylon Finance Protocol
 *
 * 1Inch protocol trade integration
 */
contract OneInchTradeIntegration is TradeIntegration {
    using SafeMath for uint256;

    /* ============ State Variables ============ */

    // Address of 1Inch exchange address
    address public oneInchExchangeAddress;

    // Bytes to check 1Inch function signature
    bytes4 public immutable oneInchFunctionSignature = bytes4(0xe2a7515e);

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _weth                         Address of the WETH ERC20
     * @param _controller                   Address of the controller
     * @param _oneInchExchangeAddress       Address of 1inch exchange contract
     */
    constructor(
        address _controller,
        address _weth,
        address _oneInchExchangeAddress
    ) TradeIntegration('1inch', _weth, _controller) {
        oneInchExchangeAddress = _oneInchExchangeAddress;
    }

    /* ============ External Functions ============ */

    function updateExchangeAddress(address _newExchangeAddress) public onlyProtocol {
        oneInchExchangeAddress = _newExchangeAddress;
    }

    /* ============ Internal Functions ============ */

    /**
     * Executes the trade through 1Inch.
     *
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of reserve asset token sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     * @param _minReceiveQuantity   Min units of wanted token to be received from the exchange
     */
    function _executeTrade(
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) internal override returns (uint256) {
        (uint256 _returnAmount, uint256[] memory _distribution) =
            IOneInchExchange(oneInchExchangeAddress).getExpectedReturn(
                _sendToken,
                _receiveToken,
                _sendQuantity,
                _sendQuantity.div(1e18),
                0
            );
        uint256 _resultAmount =
            IOneInchExchange(oneInchExchangeAddress).swap(
                _sendToken,
                _receiveToken,
                _sendQuantity,
                _returnAmount,
                _distribution,
                0
            );
        require(_resultAmount >= _minReceiveQuantity, '1Inch trade had more slippage than allowed');
        return _resultAmount;
    }

    /**
     * Returns the address to approve source tokens to for trading. This is the TokenTaker address
     *
     * @return address             Address of the contract to approve tokens to
     */
    function _getSpender() internal view override returns (address) {
        return oneInchExchangeAddress;
    }
}
