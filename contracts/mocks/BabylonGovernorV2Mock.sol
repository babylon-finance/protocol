// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.2;

import 'contracts-next/governance/Governor.sol';
import 'contracts-next/governance/extensions/GovernorProposalThreshold.sol';
import 'contracts-next/governance/extensions/GovernorCountingSimple.sol';
import 'contracts-next/governance/extensions/GovernorVotesComp.sol';
import 'contracts-next/governance/extensions/GovernorTimelockControl.sol';

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
