// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IBabylonGate} from './IBabylonGate.sol';

/**
 * @title IIshtarGate
 * @author Babylon Finance
 *
 * Interface for interacting with the Gate Guestlist NFT
 */
interface IIshtarGate is IBabylonGate {
    /* ============ Functions ============ */

    function tokenURI() external view returns (string memory);

    function updateGardenURI(string memory _tokenURI) external;
}
