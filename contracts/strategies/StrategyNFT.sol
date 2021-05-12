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

import {ERC721Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol';
import {Counters} from '@openzeppelin/contracts/utils/Counters.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IStrategyNFT} from '../interfaces/IStrategyNFT.sol';

/**
 * @title StrategyNFT
 * @author Babylon Finance
 *
 * Contract the NFT for each Strategy
 */
contract StrategyNFT is ERC721Upgradeable, IStrategyNFT {
    using Counters for Counters.Counter;

    /* ============ Events ============ */

    event StrategyNFTAwarded(address indexed _member, uint256 indexed _newItemId);
    event StrategyURIUpdated(string _newValue, string _oldValue);

    /* ============ Modifiers ============ */

    modifier onlyStrategy {
        require(IGarden(strategy.garden()).isStrategyActiveInGarden(msg.sender), 'Only the strategy can mint the NFT');
        _;
    }

    /* ============ State Variables ============ */

    // Address of the Controller contract
    IBabController public controller;
    IGarden public garden;
    IStrategy public strategy;

    // Address of the Strategy NFT JSON
    string public strategyTokenURI;

    Counters.Counter private _tokenIds;

    /* ============ Constructor ============ */

    /**
     * Sets the protocol controller
     *
     * @param _controller         Address of controller contract
     * @param _strategy           Address of the strategy this NFT belongs to
     * @param _name               Name of the garden
     * @param _symbol             Symbol of the garden
     */
    function initialize(
        address _controller,
        address _strategy,
        string memory _name,
        string memory _symbol
    ) external override initializer {
        require(address(_controller) != address(0), 'Controller must exist');
        require(bytes(_name).length < 50, 'Strategy Name is too long');
        __ERC721_init(_name, _symbol);
        controller = IBabController(_controller);
        strategy = IStrategy(_strategy);
    }

    /* ============ External Functions ============ */

    /**
     * Awards the garden NFT to a user and gives him access to a specific garden
     *
     * @param _user               Address of the user
     */
    function grantStrategyNFT(address _user, string memory _strategyTokenURI) external override onlyStrategy returns (uint256) {
        require(address(_user) != address(0), 'User must exist');
        _updateStrategyURI(_strategyTokenURI);
        return _createOrGetStrategyNFT(_user);
    }

    /**
     * Updates the token URI of the garden NFT
     *
     * @param _strategyTokenURI               Address of the strategyTokenURI
     */
    function updateStrategyURI(string memory _strategyTokenURI) external override {
        require(msg.sender == controller.owner(), 'Only owner can call this');
        _updateStrategyURI(_strategyTokenURI);
    }

    /* ============ Internal Functions ============ */

    /**
     * Gives a new nft to the user or retrieve the existing one
     *
     * @param _user               Address of the user
     */
    function _createOrGetStrategyNFT(address _user) private returns (uint256) {
        uint256 newItemId = 0;
        if (balanceOf(_user) == 0) {
            _tokenIds.increment();
            newItemId = _tokenIds.current();
            _safeMint(_user, newItemId);
            _setTokenURI(newItemId, strategyTokenURI);
            emit StrategyNFTAwarded(_user, newItemId);
        } else {
            newItemId = tokenOfOwnerByIndex(_user, 0);
        }
        return newItemId;
    }

    /**
     * Updates the token URI of the strategy NFT
     *
     * @param _strategyTokenURI               Address of the strategyTokenURI
     */
    function _updateStrategyURI(string memory _strategyTokenURI) private {
        string memory oldURI = strategyTokenURI;
        strategyTokenURI = _strategyTokenURI;
        emit StrategyURIUpdated(strategyTokenURI, oldURI);
    }
}
