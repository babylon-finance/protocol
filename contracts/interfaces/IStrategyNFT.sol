// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IGarden} from './IGarden.sol';
import {IBabController} from './IBabController.sol';

/**
 * @title IStrategyNFT
 * @author Babylon Finance
 *
 * Interface for operating with a Strategy NFT.
 */
interface IStrategyNFT {
    struct StratDetail {
        string name;
        string symbol;
        uint256 tokenId;
    }

    function grantStrategyNFT(address _user, string memory _strategyTokenURI) external returns (uint256);

    function saveStrategyNameAndSymbol(
        address _strategy,
        string memory _name,
        string memory _symbol
    ) external;

    function getStrategyTokenURI(address _stratgy) external view returns (string memory);

    function getStrategyName(address _strategy) external view returns (string memory);
}
