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

import 'hardhat/console.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';

import {IGardenFactory} from '../interfaces/IGardenFactory.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {Garden} from './Garden.sol';
import {GardenNFT} from './GardenNFT.sol';

/**
 * @title GardenFactory
 * @author Babylon Finance
 *
 * Factory to create garden contracts
 */
contract GardenFactory is IGardenFactory {
    address private immutable controller;
    address private immutable garden;

    constructor(address _controller) {
        require(_controller != address(0), 'Controller is zero');

        controller = _controller;
        garden = address(new Garden());
    }

    /**
     * Creates a garden using minimal proxies
     * @param _reserveAsset           Address of the reserve asset ERC20
     * @param _creator                Address of the creator
     * @param _name                   Name of the Garden
     * @param _symbol                 Symbol of the Garden
     * @param _tokenURI               URL of the garden NFT JSON
     * @param _seed                   Seed to regenerate the garden NFT
     * @param _gardenParams           Array of numeric params in the garden
     * @param _initialContribution    Initial Contribution by the Gardener
     */
    function createGarden(
        address _reserveAsset,
        address _creator,
        string memory _name,
        string memory _symbol,
        string memory _tokenURI,
        uint256 _seed,
        uint256[] calldata _gardenParams,
        uint256 _initialContribution
    ) external override returns (address) {
        require(msg.sender == controller, 'Only the controller can create gardens');
        address payable clone = payable(Clones.clone(garden));
        Garden(clone).initialize(
            _reserveAsset,
            controller,
            _creator,
            _name,
            _symbol,
            _gardenParams,
            _initialContribution
        );
        GardenNFT(IBabController(controller).gardenNFT()).saveGardenURIAndSeed(clone, _tokenURI, _seed);
        return clone;
    }
}
