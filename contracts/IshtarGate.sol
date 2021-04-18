/*
    Copyright 2021 Babylon Finance

    Modified from (Set Protocol SetValuer)

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

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ERC721} from '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {Counters} from '@openzeppelin/contracts/utils/Counters.sol';
import {IBabController} from './interfaces/IBabController.sol';
import {IIshtarGate} from './interfaces/IIshtarGate.sol';
import {IGarden} from './interfaces/IGarden.sol';

/**
 * @title IshtarGate
 * @author Babylon Finance
 *
 * Contract that implements guestlists for Babylon Finance using an NFT
 */
contract IshtarGate is ERC721, IIshtarGate, Ownable {
    using Counters for Counters.Counter;
    using SafeMath for uint256;

    /* ============ Events ============ */

    event IshtarGateAwarded(address indexed _member, uint256 indexed _newItemId);
    event GardenAccess(address indexed _member, address indexed _garden, uint8 _permission, uint256 _tokenId);
    event GardenCreationPower(address indexed _member, bool _creation, uint256 _tokenId);

    /* ============ State Variables ============ */

    // Address of the Controller contract
    IBabController public controller;

    // Address of the Ishtar Gate JSON (Shared JSON)
    string public tokenURI;

    // Permissions by community user
    mapping(address => mapping(address => uint8)) public permissionsByCommunity;
    mapping(address => bool) public canCreateAGarden;
    mapping(address => uint256) public gardenAccessCount;

    uint8 public constant NONE = 0;
    uint8 public constant JUST_LP = 1;
    uint8 public constant STEWARD = 2;
    uint8 public constant STRATEGIST = 3;

    Counters.Counter private _tokenIds;

    /* ============ Modifiers ============ */

    modifier onlyGardenCreator(address _garden) {
        require(address(_garden) != address(0), 'Garden must exist');
        IGarden garden = IGarden(_garden);
        require(garden.controller() == address(controller), 'Controller must match');
        require(msg.sender == garden.creator(), 'Only creator can give access to garden');
        require(
            gardenAccessCount[_garden] < garden.maxContributors(),
            'The number of contributors must be below the limit'
        );
        _;
    }

    /* ============ Constructor ============ */

    /**
     * Sets the protocol controller
     *
     * @param _controller         Address of controller contract
     * @param _tokenURI           URL of the Ishtar Gate JSON metadata
     */
    constructor(IBabController _controller, string memory _tokenURI) ERC721('IshtarGate', 'ISHT') {
        require(address(_controller) != address(0), 'Controller must exist');
        controller = _controller;
        tokenURI = _tokenURI;
    }

    /* ============ External Functions ============ */

    /**
     * Awards the ishtar gate to a user and gives him access to a specific garden
     *
     * @param _user               Address of the user
     * @param _garden             Community that the gate grants access to
     * @param _permission        Permissions of what user can do in the community
     */
    function setGardenAccess(
        address _user,
        address _garden,
        uint8 _permission
    ) external override onlyGardenCreator(_garden) returns (uint256) {
        require(address(_user) != address(0), 'User must exist');
        return _setIndividualGardenAccess(_user, _garden, _permission);
    }

    /**
     * Awards the ishtar gate to a list of users with permissions to a specific garden
     *
     * @param _garden             Community that the gate grants access to
     * @param _users              Addresses of the users
     * @param _perms              List of permissions of what each user can do in the community
     */
    function grantGardenAccessBatch(
        address _garden,
        address[] calldata _users,
        uint8[] calldata _perms
    ) external override onlyGardenCreator(_garden) returns (bool) {
        require(_users.length == _perms.length, 'Permissions and users must match');
        for (uint8 i = 0; i < _users.length; i++) {
            _setIndividualGardenAccess(_users[i], _garden, _perms[i]);
        }
        return true;
    }

    /**
     * Awards the ishtar gate to a user and give/remove him garden creation capabilities.
     *
     * @param _user               Address of the user
     * @param _canCreate          Boolean with permissions as to whether the user can create gardens
     */
    function setCreatorPermissions(address _user, bool _canCreate) external override onlyOwner returns (uint256) {
        _setCreatorPermissions(_user, _canCreate);
    }

    /**
     * Awards the ishtar gate to a list of users with permissions to create gardens
     *
     * @param _garden             Community that the gate grants access to
     * @param _users              Addresses of the users
     * @param _perms              Lists of booleans
     */
    function grantCreatorsInBatch(
        address _garden,
        address[] calldata _users,
        bool[] calldata _perms
    ) external override onlyOwner returns (bool) {
        require(_users.length == _perms.length, 'Permissions and users must match');
        for (uint8 i = 0; i < _users.length; i++) {
            _setCreatorPermissions(_users[i], _perms[i]);
        }
        return true;
    }

    /**
     * Check if a user can create gardens
     *
     * @param _user                     Address of the user
     * @return _canCreate               Whether or not the user can create
     */
    function canCreate(address _user) external override returns (bool) {
        return canCreateAGarden[_user];
    }

    /**
     * Check if a user can join a specific garden
     *
     * @param _user                       Address of the user
     * @param _garden                     Address of the _garden
     * @return _canJoin                   Whether or not the user can join
     */
    function canJoinAGarden(address _garden, address _user) external override returns (bool) {
        return permissionsByCommunity[_garden][_user] >= JUST_LP;
    }

    /**
     * Check if a user can vote in a specific garden
     *
     * @param _user                       Address of the user
     * @param _garden                     Address of the _garden
     * @return _canVote                   Whether or not the user can vote
     */
    function canVoteInAGarden(address _garden, address _user) external override returns (bool) {
        return permissionsByCommunity[_garden][_user] >= STEWARD;
    }

    /**
     * Check if a user can add strategies in a specific garden
     *
     * @param _user                       Address of the user
     * @param _garden                     Address of the _garden
     * @return _canStrategize             Whether or not the user can create strategies
     */
    function canAddStrategiesInAGarden(address _garden, address _user) external override returns (bool) {
        return permissionsByCommunity[_garden][_user] >= STRATEGIST;
    }

    /* ============ Internal Functions ============ */

    /**
     * Gives a new gate to the user or retrieve the existing one
     *
     * @param _user               Address of the user
     */
    function _createOrGetGateNFT(address _user) private returns (uint256) {
        uint256 newItemId = 0;
        if (balanceOf(_user) == 0) {
            _tokenIds.increment();
            newItemId = _tokenIds.current();
            _mint(_user, newItemId);
            _setTokenURI(newItemId, tokenURI);
            emit IshtarGateAwarded(_user, newItemId);
        } else {
            newItemId = tokenOfOwnerByIndex(_user, 0);
        }
        return newItemId;
    }

    /**
     * Awards the ishtar gate to a user and gives him access to a specific garden
     *
     * @param _user               Address of the user
     * @param _garden             Community that the gate grants access to
     * @param _permission        Permissions of what user can do in the community
     */
    function _setIndividualGardenAccess(
        address _user,
        address _garden,
        uint8 _permission
    ) private returns (uint256) {
        uint256 newItemId = _createOrGetGateNFT(_user);
        if (_permission > 0 && permissionsByCommunity[_garden][_user] == 0) {
            gardenAccessCount[_garden] = gardenAccessCount[_garden].add(1);
        }
        if (_permission == 0 && permissionsByCommunity[_garden][_user] > 0) {
            gardenAccessCount[_garden] = gardenAccessCount[_garden].sub(1);
        }
        permissionsByCommunity[_garden][_user] = _permission;
        emit GardenAccess(_user, _garden, _permission, newItemId);
        return newItemId;
    }

    /**
     * Awards the ishtar gate to a user and give/remove him garden creation capabilities.
     *
     * @param _user               Address of the user
     * @param _canCreate          Boolean with permissions as to whether the user can create gardens
     */
    function _setCreatorPermissions(address _user, bool _canCreate) private returns (uint256) {
        require(address(_user) != address(0), 'User must exist');
        uint256 newItemId = _createOrGetGateNFT(_user);
        canCreateAGarden[_user] = _canCreate;
        emit GardenCreationPower(_user, _canCreate, newItemId);
        return newItemId;
    }
}
