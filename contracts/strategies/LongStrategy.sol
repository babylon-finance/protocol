/*
    Copyright 2020 Babylon Finance.

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
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Strategy} from './Strategy.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {ITradeIntegration} from '../interfaces/ITradeIntegration.sol';

/**
 * @title LongStrategy
 * @author Babylon Finance
 *
 * Holds the data for a long strategy
 */
contract LongStrategy is Strategy {
    address public sendToken; // Asset to exchange
    address public receiveToken; // Asset to receive
    uint256 public sendTokenQuantity; // Quantity of send token to sell
    uint256 public minReceiveQuantity; // Min quantity of receive token to receive

    /**
     * Sets integration data for the long strategy
     *
     * @param _sendToken                      Token to be exchanged
     * @param _receiveToken                   Token to be bought
     * @param _sendToken                      Amount of sendToken to sell
     * @param _minReceiveQuantity             Min amount of receiveToken to get
     */
    function setLongData(
        address _sendToken,
        address _receiveToken,
        uint256 _sendTokenQuantity,
        uint256 _minReceiveQuantity
    ) public onlyIdeator {
        kind = 0;
        require(!dataSet, 'Data is set already');
        require(_minReceiveQuantity > 0, 'Must receive assets back');
        require(_sendToken != _receiveToken, 'Receive token must be different');
        sendToken = _sendToken;
        receiveToken = _receiveToken;
        sendTokenQuantity = _sendTokenQuantity;
        minReceiveQuantity = _minReceiveQuantity;
        dataSet = true;
    }

    /**
     * Enters the long strategy
     */
    function _enterStrategy() internal override {
        ITradeIntegration(integration).trade(
            sendToken,
            sendTokenQuantity,
            receiveToken,
            minReceiveQuantity // TODO: Can we trust the integration or check first with TWAP
        );
    }

    /**
     * Exits the long strategy.
     */
    function _exitStrategy() internal override {
        ITradeIntegration(integration).trade(
            receiveToken,
            IERC20(receiveToken).balanceOf(address(this)),
            sendToken,
            minReceiveQuantity // TODO: calculate this with oracle or 1inch
        );
    }
}
