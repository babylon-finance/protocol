// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.9;

import {ERC721} from '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import {ERC721URIStorage} from '@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol';
import {ERC721Enumerable} from '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
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
contract StrategyNFT is ERC721, ERC721URIStorage, ERC721Enumerable, IStrategyNFT {
    using Counters for Counters.Counter;

    /* ============ Events ============ */

    event StrategyNFTAwarded(address indexed _member, uint256 indexed _newItemId);

    /* ============ Modifiers ============ */

    modifier onlyStrategy {
        IStrategy strategy = IStrategy(msg.sender);
        require(
            IGarden(strategy.garden()).strategyMapping(msg.sender) && controller.isSystemContract(msg.sender),
            'Only the strategy can mint the NFT'
        );
        _;
    }

    /* ============ State Variables ============ */

    // Address of the Controller contract
    IBabController public controller;

    mapping(address => StratDetail) public stratDetails;

    Counters.Counter private _tokenIds;

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
        require(bytes(_name).length < 50, 'Strategy Name is too long');
        controller = IBabController(_controller);
    }

    /* ============ External Functions ============ */

    /**
     * Awards the garden NFT to a user and gives him access to a specific garden
     *
     * @param _user                           Address of the user
     * @param _strategyTokenURI               Strategy token URI
     */
    function grantStrategyNFT(address _user, string memory _strategyTokenURI)
        external
        override
        onlyStrategy
        returns (uint256)
    {
        require(address(_user) != address(0), 'User must exist');
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _safeMint(_user, newItemId);
        _setTokenURI(newItemId, _strategyTokenURI);
        stratDetails[msg.sender].tokenId = newItemId;
        emit StrategyNFTAwarded(_user, newItemId);
        return newItemId;
    }

    /**
     * Saves the name an symbol for a new created strategy
     *
     * @param _strategy               Address of the strategy
     * @param _name                   Strategy Name
     * @param _symbol                 Strategy Symbol
     */
    function saveStrategyNameAndSymbol(
        address _strategy,
        string memory _name,
        string memory _symbol
    ) external override {
        require(controller.isSystemContract(msg.sender), 'Only a system contract can call this');
        StratDetail storage stratDetail = stratDetails[_strategy];
        stratDetail.name = _name;
        stratDetail.symbol = _symbol;
    }

    function getStrategyTokenURI(address _strategy) external view override returns (string memory) {
        return tokenURI(stratDetails[_strategy].tokenId);
    }

    function getStrategyName(address _strategy) external view override returns (string memory) {
        return stratDetails[_strategy].name;
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
