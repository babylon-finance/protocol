// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {ICurveMetaRegistry} from './ICurveMetaRegistry.sol';

/**
 * @title IPriceOracle
 * @author Babylon Finance
 *
 * Interface for interacting with PriceOracle
 */
interface ITokenIdentifier {
    /* ============ Functions ============ */

    function identifyTokens(
        address _tokenIn,
        address _tokenOut
    )
        external
        view
        returns (
            uint8,
            uint8,
            address,
            address
        );

    function updateVisor(address[] calldata _vaults, bool[] calldata _values) external;

    function refreshAAveReserves() external;

    function refreshCompoundTokens() external;

    function updateYearnVaults() external;

    function updatePickleJars() external;
}
