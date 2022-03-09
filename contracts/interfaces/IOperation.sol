// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IGarden} from './IGarden.sol';
import {IStrategy} from './IStrategy.sol';

/**
 * @title IOperation
 * @author Babylon Finance
 *
 * Interface for an strategy operation
 */
interface IOperation {
    function validateOperation(
        bytes calldata _data,
        IGarden _garden,
        address _integration,
        uint256 _index
    ) external view;

    function executeOperation(
        address _asset,
        uint256 _capital,
        uint8 _assetStatus,
        bytes calldata _data,
        IGarden _garden,
        address _integration
    )
        external
        returns (
            address,
            uint256,
            uint8
        );

    function exitOperation(
        address _asset,
        uint256 _remaining,
        uint8 _assetStatus,
        uint256 _percentage,
        bytes calldata _data,
        IGarden _garden,
        address _integration
    )
        external
        returns (
            address,
            uint256,
            uint8
        );

    function getNAV(
        bytes calldata _data,
        IGarden _garden,
        address _integration
    ) external view returns (uint256, bool);

    function getName() external view returns (string memory);
}
