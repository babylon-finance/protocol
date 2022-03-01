// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.9;

import {ERC721URIStorage} from '@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol';
import {ERC721Enumerable} from '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
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
contract GardenNFT is ERC721URIStorage, ERC721Enumerable, IGardenNFT {
    using Counters for Counters.Counter;

    /* ============ Events ============ */

    event GardenNFTAwarded(address indexed _member, uint256 indexed _newItemId);

    /* ============ Modifiers ============ */

    modifier onlyGarden {
        require(
            controller.isSystemContract(msg.sender) && IGarden(msg.sender).controller() == controller,
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
    ) ERC721Enumerable(_name, _symbol) {
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
