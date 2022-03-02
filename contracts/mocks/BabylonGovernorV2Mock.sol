// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.5;

import '@openzeppelin/contracts/governance/Governor.sol';
import '@openzeppelin/contracts/governance/compatibility/GovernorCompatibilityBravo.sol';
import '@openzeppelin/contracts/governance/extensions/GovernorVotesComp.sol';
import '@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol';

import {BabylonGovernor} from '../governance/BabylonGovernor.sol';

contract BabylonGovernorV2 is BabylonGovernor {
    uint256 public answer;

    /* ============ Constructor ============ */

    /**
     * @dev Sets the value for {name} and {version}
     */
    constructor(ERC20VotesComp _token, TimelockController _timeLockAddress) BabylonGovernor(_token, _timeLockAddress) {
        answer = 42;
    }
}
