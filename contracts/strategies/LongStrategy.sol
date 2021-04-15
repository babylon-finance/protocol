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

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Strategy} from './Strategy.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {ITradeIntegration} from '../interfaces/ITradeIntegration.sol';

/**
 * @title LongStrategy
 * @author Babylon Finance
 *
 * Holds the data for a long strategy
 */
contract LongStrategy is Strategy {
    using PreciseUnitMath for uint256;

    address public longToken; // Asset to receive

    /**
     * Sets integration data for the long strategy
     *
     * @param _longToken                   Token to be bought
     */
    function setData(address _longToken) external onlyGardenAndNotSet {
        require(garden.reserveAsset() != _longToken, 'Receive token must be different');

        kind = 0;
        longToken = _longToken;
        dataSet = true;
    }

    /**
     * Gets the NAV of the long asset in ETH
     *
     * @return _nav           NAV of the strategy
     */
    function getNAV() public view override returns (uint256) {
        if (!active || finalized) {
            return 0;
        }
        uint256 price = _getPrice(garden.reserveAsset(), longToken);
        uint256 NAV = IERC20(longToken).balanceOf(address(this)).preciseDiv(price);
        require(NAV != 0, 'NAV has to be bigger 0');
        return NAV;
    }

    /**
     * Enters the long strategy
     * @param _capital      Amount of capital received from the garden
     */
    function _enterStrategy(uint256 _capital) internal override {
        _trade(garden.reserveAsset(), _capital, longToken);
    }

    /**
     * Exits the long strategy.
     * @param _percentage of capital to exit from the strategy
     */
    function _exitStrategy(uint256 _percentage) internal override {
        require(_percentage <= HUNDRED_PERCENT, 'Unwind Percentage <= 100%');
        _trade(longToken, IERC20(longToken).balanceOf(address(this)).preciseMul(_percentage), garden.reserveAsset());
    }
}
