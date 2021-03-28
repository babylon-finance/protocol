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
import {IPoolIntegration} from '../interfaces/IPoolIntegration.sol';

/**
 * @title LongStrategy
 * @author Babylon Finance
 *
 * Holds the data for a strategy that adds liquidity to a pool
 */
contract LiquidityPoolStrategy is Strategy {
    address public sendToken;           // Address of token to sell to buy the pool tokens
    address public pool;                // Pool to add liquidity to
    uint256 public sendTokenQuantity;   // Amount of send token to sell
    uint256 public minReceiveQuantity;  // Min amount of pool tokens to receive

    /**
     * Sets integration data for the pool strategy
     *
     * @param _sendToken                      Address of token to sell
     * @param _pool                           Liquidity pool
     * @param _sendTokenQuantity              Amount of sendToken to sell
     * @param _minReceiveQuantity             Min amount of pool tokens to get
     */
    function setPoolData(
        address _sendToken,
        address _pool,
        uint256 _sendTokenQuantity,
        uint256 _minReceiveQuantity
    ) public onlyIdeator {
        kind = 1;
        require(_minReceiveQuantity > 0, 'Must receive assets back');
        require(pool != _sendToken, 'Pool token must be different');
        // TODO: Validate pool
        sendToken = _sendToken;
        pool = _pool;
        sendTokenQuantity = _sendTokenQuantity;
        minReceiveQuantity = _minReceiveQuantity;
    }

    /**
     * Enters the pool strategy
     */
    function _enterStrategy() internal override {

    }

    /**
     * Exits the pool strategy.
     */
    function _exitStrategy() internal override {

    }
}
