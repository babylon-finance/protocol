// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

/**
 * @title ILiquidation
 * @author Babylon Finance
 *
 * Interface for interacting with the liquidation process
 */
interface ILiquidation {
    /* ============ Functions ============ */

    function addToWhitelist() external;

    function claimProceeds() external;
}
