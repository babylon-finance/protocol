// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.9;

/**
 * @title IIntegration
 * @author Babylon Finance
 *
 * Interface for protocol integrations
 */
interface IIntegration {
    function getName() external view returns (string memory);
}
