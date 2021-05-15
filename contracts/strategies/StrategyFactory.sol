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

pragma solidity 0.7.6;

import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';

import {IStrategy} from '../interfaces/IStrategy.sol';
import {IStrategyFactory} from '../interfaces/IStrategyFactory.sol';
import {StrategyNFT} from './StrategyNFT.sol';
import {Strategy} from './Strategy.sol';

/**
 * @title StrategyFactory
 * @author Babylon Finance
 *
 * Factory to create investment strategy contracts
 */
contract StrategyFactory is IStrategyFactory {
    address private immutable controller;
    address payable private immutable strategy;
    address private immutable strategyNft;

    constructor(address _controller) {
        require(_controller != address(0), 'Controller is zero');

        controller = _controller;
        strategy = address(new Strategy());
        strategyNft = address(new StrategyNFT());
    }

    /**
     * Creates a new investment strategy using minimal proxies
     *
     * @param _name                          Name of the strategy
     * @param _symbol                        Symbol of the strategy
     * @param _strategist                    Address of the strategist
     * @param _garden                        Address of the garden
     * @param _stratParams                   Strat Params
     */
    function createStrategy(
        string memory _name,
        string memory _symbol,
        address _strategist,
        address _garden,
        uint256[] calldata _stratParams
    ) external override returns (address) {
        address payable clone = payable(Clones.clone(strategy));
        address cloneNFT = Clones.clone(strategyNft);
        StrategyNFT(cloneNFT).initialize(controller, address(clone), _name, _symbol);
        IStrategy(clone).initialize(
            _strategist,
            _garden,
            controller,
            _stratParams[0],
            _stratParams[1],
            _stratParams[2],
            _stratParams[3],
            _stratParams[4],
            cloneNFT
        );
        return clone;
    }
}
