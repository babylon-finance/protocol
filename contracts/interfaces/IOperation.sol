// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {IGarden} from './IGarden.sol';
import {IStrategy} from './IStrategy.sol';

/**
 * @title IOperation
 * @author Babylon Finance
 *
 * Interface for an strategy operation
 */
interface IOperation {
    struct Args {
        address asset;
        uint256 capital;
        uint8 assetStatus;
        bytes data;
        IGarden garden;
        address integration;
    }

    function validateOperation(
        bytes calldata _data,
        IGarden _garden,
        address _integration,
        uint256 _index
    ) external view;

    function executeOperation(Args memory args, uint256[] memory _prices, IStrategy.TradeInfo[] memory _trades)
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
