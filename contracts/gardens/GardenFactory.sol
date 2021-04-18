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

import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';

import {IGardenFactory} from '../interfaces/IGardenFactory.sol';
import {Garden} from './Garden.sol';

/**
 * @title GardenFactory
 * @author Babylon Finance
 *
 * Factory to create garden contracts
 */
contract GardenFactory is IGardenFactory {
    address private immutable garden;

    constructor() {
        garden = address(new Garden());
    }

    /**
     * Creates a garden using minimal proxies
     * @param _reserveAsset           Address of the reserve asset ERC20
     * @param _controller             Address of the controller
     * @param _creator                Address of the creator
     * @param _name                   Name of the Garden
     * @param _symbol                 Symbol of the Garden
     */
    function createGarden(
        address _reserveAsset,
        address _controller,
        address _creator,
        string memory _name,
        string memory _symbol
    ) external override returns (address) {
        address payable clone = payable(Clones.clone(garden));
        Garden(clone).initialize(_reserveAsset, _controller, _creator, _name, _symbol);
        return clone;
    }
}
