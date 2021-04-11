/*
    Copyright 2021 Babylon Finance.

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
    address public longToken; // Asset to receive

    /**
     * Sets integration data for the long strategy
     *
     * @param _longToken                   Token to be bought
     */
    function setData(address _longToken) public onlyGardenAndNotSet {
        require(!dataSet, 'Data is set already');
        require(garden.reserveAsset() != _longToken, 'Receive token must be different');

        kind = 0;
        longToken = _longToken;
        dataSet = true;
    }

    /**
     * Enters the long strategy
     */
    function _enterStrategy(uint256 _capital) internal override {
        _trade(garden.reserveAsset(), _capital, longToken);
    }

    /**
     * Exits the long strategy.
     */
    function _exitStrategy() internal override {
        _trade(longToken, IERC20(longToken).balanceOf(address(this)), garden.reserveAsset());
    }
}
