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
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';
import {TradeIntegration} from './TradeIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';

/**
 * @title UniswapV2TradeIntegration
 * @author Babylon Finance Protocol
 *
 * UniswapV3 trade integration
 */
contract UniswapV2TradeIntegration is TradeIntegration {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    /* ============ Constants ============ */
    // Address of Uniswap V2 SwapRouter contract
    address private constant factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) TradeIntegration('univ2', _controller) {}

    /* ============ Internal Functions ============ */

    /**
     * Executes the trade through UniswapV2.
     *
     * @param _strategy             Address of the strategy
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of reserve asset token sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     * @param _hopToken             Address of the routing token for multi-hop, i.e., sendToken->hopToken->receiveToken
     */
    function _getTradeCallData(
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        address _hopToken
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
        address[] memory path;
        if (_hopToken == address(0) || _sendToken == _hopToken || _receiveToken == _hopToken) {
            path = new address[](2);
            path[0] = _sendToken;
            path[1] = _receiveToken;
        } else {
            path = new address[](3);
            path[0] = _sendToken;
            path[1] = _hopToken;
            path[2] = _receiveToken;
        }
        bytes memory callData =
            abi.encodeWithSignature(
                'swapExactTokensForTokens(uint256,uint256,address[],address,uint256)',
                _sendQuantity,
                1,
                path,
                _strategy,
                block.timestamp
            );
        return (router, 0, callData);
    }

    /**
     * Executes the trade through UniswapV2.
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
        return _getTradeCallData(_strategy, _sendToken, _sendQuantity, _receiveToken, WETH);
    }

    /**
     * Returns the address to approve source tokens to for trading. This is the TokenTaker address
     *
     * @return address             Address of the contract to approve tokens to
     */
    function _getSpender(
        address /* _swapTarget */
    ) internal pure override returns (address) {
        return router;
    }

    /* ============ Private Functions ============ */
}
