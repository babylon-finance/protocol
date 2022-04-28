// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {ITradeIntegration} from './ITradeIntegration.sol';

/**
 * @title IIshtarGate
 * @author Babylon Finance
 *
 * Interface for interacting with the Gate Guestlist NFT
 */
interface IMasterSwapper {
    /* ============ Functions ============ */

    function trade(
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) external returns (uint256);

    function isTradeIntegration(address _integration) external view returns (bool);
}
