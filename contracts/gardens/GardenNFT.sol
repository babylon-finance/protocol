/*
    Copyright 2021 Babylon Finance

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
import {ERC721} from '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import {Counters} from '@openzeppelin/contracts/utils/Counters.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IGardenNFT} from '../interfaces/IGardenNFT.sol';

/**
 * @title GardenNFT
 * @author Babylon Finance
 *
 * Contract the NFT for each Garden
 */
contract GardenNFT is ERC721, IGardenNFT {
    using Counters for Counters.Counter;

    /* ============ Events ============ */

    event GardenNFTAwarded(address indexed _member, uint256 indexed _newItemId);

    /* ============ Modifiers ============ */

    modifier onlyGarden {
        require(
            controller.isSystemContract(msg.sender) && IGarden(msg.sender).controller() == address(controller),
            'Only the garden can mint the NFT'
        );
        _;
    }

    /* ============ State Variables ============ */

    // Address of the Controller contract
    IBabController public controller;

    Counters.Counter private _tokenIds;
    mapping(address => string) public override gardenTokenURIs;
    mapping(address => uint256) public override gardenSeeds;

    /* ============ Constructor ============ */

    /**
     * Sets the protocol controller
     *
     * @param _controller         Address of controller contract
     * @param _name               Name of the garden
     * @param _symbol             Symbol of the garden
     */
    constructor(
        address _controller,
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {
        require(address(_controller) != address(0), 'Controller must exist');
        controller = IBabController(_controller);
    }

    /* ============ External Functions ============ */

    /**
     * Awards the garden NFT to a user and gives him access to a specific garden
     *
     * @param _user               Address of the user
     */
    function grantGardenNFT(address _user) external override onlyGarden returns (uint256) {
        require(address(_user) != address(0), 'User must exist');
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _safeMint(_user, newItemId);
        _setTokenURI(newItemId, gardenTokenURIs[msg.sender]);
        emit GardenNFTAwarded(_user, newItemId);
        return newItemId;
    }

    /**
     * Saves the Garden URI and seed
     *
     * @param _garden               Address of the garden
     * @param _gardenTokenURI     Garden Token URI
     */
    function saveGardenURIAndSeed(
        address _garden,
        string memory _gardenTokenURI,
        uint256 _seed
    ) external override {
        require(controller.isSystemContract(msg.sender), 'Only a system contract can call this');
        gardenTokenURIs[_garden] = _gardenTokenURI;
        gardenSeeds[_garden] = _seed;
    }
}
