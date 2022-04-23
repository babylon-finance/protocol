// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

/**
 * @title IPickleJarRegistry
 * @author Babylon Finance
 *
 * Interface for interacting with all the pickle jars
 */
interface IPickleJarRegistry {
    /* ============ Functions ============ */

    function updateJars(
        address[] calldata _jars,
        bool[] calldata _values,
        bool[] calldata _uniflags
    ) external;

    /* ============ View Functions ============ */

    function jars(address _jarAddress) external view returns (bool);

    function isUniv3(address _jarAddress) external view returns (bool);

    function getAllJars() external view returns (address[] memory);
}
