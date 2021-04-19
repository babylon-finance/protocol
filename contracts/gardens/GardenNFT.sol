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

pragma solidity 0.7.4;

import 'hardhat/console.sol';
import {ERC721Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol';
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
contract GardenNFT is ERC721Upgradeable, IGardenNFT {
    using Counters for Counters.Counter;

    /* ============ Events ============ */

    event GardenNFTAwarded(address indexed _member, uint256 indexed _newItemId);
    event GardenURIUpdated(string _newValue, string _oldValue);

    /* ============ Modifiers ============ */

    modifier onlyGarden {
        require(msg.sender == address(garden), 'Only the garden can mint the NFT');
        _;
    }

    /* ============ State Variables ============ */

    // Address of the Controller contract
    IBabController public controller;
    IGarden public garden;

    // Address of the Garden JSON (Shared JSON for each garden)
    string public tokenURI;
    uint256 public seed;

    Counters.Counter private _tokenIds;

    /* ============ Constructor ============ */

    /**
     * Sets the protocol controller
     *
     * @param _controller         Address of controller contract
     * @param _garden             Address of the garden this NFT belongs to
     * @param _name               Name of the garden
     * @param _symbol             Symbol of the garden
     * @param _tokenURI           Initial token URI
     */
    function initialize(
        address _controller,
        address _garden,
        string memory _name,
        string memory _symbol,
        string memory _tokenURI
    ) external override initializer {
        require(address(_controller) != address(0), 'Controller must exist');
        __ERC721_init(_name, _symbol);
        controller = IBabController(_controller);
        garden = IGarden(_garden);
        seed = garden.gardenInitializedAt();
        tokenURI = _tokenURI;
    }

    /* ============ External Functions ============ */

    /**
     * Awards the garden NFT to a user and gives him access to a specific garden
     *
     * @param _user               Address of the user
     */
    function grantGardenNFT(address _user) external override onlyGarden returns (uint256) {
        require(address(_user) != address(0), 'User must exist');
        return _createOrGetGardenNFT(_user);
    }

    /**
     * Updates the token URI of the garden NFT
     *
     * @param _tokenURI               Address of the tokenURI
     */
    function updateGardenURI(string memory _tokenURI) external override {
        require(msg.sender == controller.owner(), 'Only owner can call this');
        string memory oldURI = tokenURI;
        tokenURI = _tokenURI;
        emit GardenURIUpdated(tokenURI, oldURI);
    }

    /* ============ Internal Functions ============ */

    /**
     * Gives a new nft to the user or retrieve the existing one
     *
     * @param _user               Address of the user
     */
    function _createOrGetGardenNFT(address _user) private returns (uint256) {
        uint256 newItemId = 0;
        if (balanceOf(_user) == 0) {
            _tokenIds.increment();
            newItemId = _tokenIds.current();
            _safeMint(_user, newItemId);
            _setTokenURI(newItemId, tokenURI);
            emit GardenNFTAwarded(_user, newItemId);
        } else {
            newItemId = tokenOfOwnerByIndex(_user, 0);
        }
        return newItemId;
    }
}
