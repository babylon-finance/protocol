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

import {UpgradeableBeacon} from '@openzeppelin/contracts/proxy/UpgradeableBeacon.sol';

import {SafeBeaconProxy} from '../proxy/SafeBeaconProxy.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IStrategyNFT} from '../interfaces/IStrategyNFT.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IStrategyFactory} from '../interfaces/IStrategyFactory.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IGarden} from '../interfaces/IGarden.sol';

/**
 * @title StrategyFactory
 * @author Babylon Finance
 *
 * Factory to create investment strategy contracts
 */
contract StrategyFactory is IStrategyFactory {
    modifier onlyGarden {
        require(
            controller.isGarden(msg.sender) && IGarden(msg.sender).controller() == controller,
            'Only the garden can create strategies'
        );
        _;
    }

    IBabController private immutable controller;
    UpgradeableBeacon private immutable beacon;

    constructor(IBabController _controller, UpgradeableBeacon _beacon) {
        require(address(_controller) != address(0), 'Controller is zero');
        require(address(_beacon) != address(0), 'Beacon is zero');

        controller = IBabController(_controller);
        beacon = _beacon;
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
    ) external override onlyGarden returns (address) {
        address payable proxy =
            payable(
                new SafeBeaconProxy(
                    address(beacon),
                    abi.encodeWithSelector(
                        IStrategy.initialize.selector,
                        _strategist,
                        _garden,
                        controller,
                        _stratParams[0],
                        _stratParams[1],
                        _stratParams[2],
                        _stratParams[3],
                        _stratParams[4],
                        _stratParams[5],
                        _stratParams[6]
                    )
                )
            );
        IStrategyNFT(controller.strategyNFT()).saveStrategyNameAndSymbol(proxy, _name, _symbol);
        return proxy;
    }
}
