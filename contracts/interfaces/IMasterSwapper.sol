// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {ITradeIntegration} from './ITradeIntegration.sol';

/**
 * @title IIshtarGate
 * @author Babylon Finance
 *
 * Interface for interacting with the Gate Guestlist NFT
 */
interface IMasterSwapper is ITradeIntegration {
    /* ============ Functions ============ */

    function isTradeIntegration(address _integration) external view returns (bool);
}
