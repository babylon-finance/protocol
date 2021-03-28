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
import {Strategy} from './Strategy.sol';
import {LongStrategy} from './LongStrategy.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';

/**
 * @title StrategyFactory
 * @author Babylon Finance
 *
 * Factory to create investment strategy contracts
 */
contract StrategyFactory {
    address immutable longStrategy;

    constructor() {
        longStrategy = address(new LongStrategy());
    }

    /**
     * Creates a new investment strategy using minimal proxies
     *
     * @param _strategist                       Address of the strategist
     * @param _garden                     Address of the garden
     * @param _controller                    Address of the controller
     * @param _maxCapitalRequested           Max Capital requested denominated in the reserve asset (0 to be unlimited)
     * @param _stake                         Stake with garden participations absolute amounts 1e18
     * @param _investmentDuration            Investment duration in seconds
     * @param _expectedReturn                Expected return
     * @param _minRebalanceCapital           Min capital that is worth it to deposit into this strategy
     */
    function createStrategy(
        uint8 _strategyKind,
        address _strategist,
        address _garden,
        address _controller,
        uint256 _maxCapitalRequested,
        uint256 _stake,
        uint256 _investmentDuration,
        uint256 _expectedReturn,
        uint256 _minRebalanceCapital
    ) external returns (address) {
        address clone;
        if (_strategyKind == 0) {
            clone = Clones.clone(longStrategy);
        }
        IStrategy(clone).initialize(
            _strategist,
            _garden,
            _controller,
            _maxCapitalRequested,
            _stake,
            _investmentDuration,
            _expectedReturn,
            _minRebalanceCapital
        );
        return clone;
    }
}
