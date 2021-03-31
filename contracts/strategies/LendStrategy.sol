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
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Strategy} from './Strategy.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {ITradeIntegration} from '../interfaces/ITradeIntegration.sol';
import {ILendIntegration} from '../interfaces/ILendIntegration.sol';

/**
 * @title LendStrategy
 * @author Babylon Finance
 *
 * Allows to supply funds to protocols (Compound, Aave) to earn interest over time.
 */
contract LendStrategy is Strategy {
    using SafeMath for uint256;

    /**
     * Sets integration data for the long strategy
     *
     * @param _lendToken                  
     */
    function setYieldFarmingData(address _yieldVault) public onlyIdeator {
        kind = 3;
        // require(IPassiveIntegration(integration).isInvestment(_yieldVault), 'Must be a valid yield vault');
        require(!dataSet, 'Data is set already');
        yieldVault = _yieldVault;
        vaultAsset = IPassiveIntegration(integration).getInvestmentAsset(_yieldVault);
        dataSet = true;
    }

    /**
     * Enters the long strategy
     */
    function _enterStrategy(uint256 _capital) internal override {
        ILendIntegration(integration).supplyTokens();
    }

    /**
     * Exits the long strategy.
     */
    function _exitStrategy() internal override {
        ILendIntegration(integration).redeemTokens();
    }
}
