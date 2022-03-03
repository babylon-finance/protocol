// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IIntegration} from './IIntegration.sol';

/**
 * @title IGardenFactory
 * @author Babylon Finance
 *
 * Interface for the garden factory
 */
interface IGardenFactory {
    function createGarden(
        address _reserveAsset,
        address _creator,
        string memory _name,
        string memory _symbol,
        string memory _tokenURI,
        uint256 _seed,
        uint256[] calldata _gardenParams,
        uint256 _initialContribution,
        bool[] memory _publicGardenStrategistsStewards
    ) external returns (address);
}
