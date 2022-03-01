// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/governance/Governor.sol';
import '@openzeppelin/contracts/governance/compatibility/GovernorCompatibilityBravo.sol';
import '@openzeppelin/contracts/governance/extensions/GovernorVotesComp.sol';
import '@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol';

import {BabylonGovernor} from '../governance/BabylonGovernor.sol';

contract BabylonGovernorMock is BabylonGovernor {
    uint256 immutable _votingDelay;
    uint256 immutable _votingPeriod;

    /* ============ Constructor ============ */

    /**
     * @dev Sets the value for {name} and {version}
     */
    constructor(
        ERC20VotesComp _token,
        TimelockController _timeLockAddress,
        uint256 votingDelay_,
        uint256 votingPeriod_
    ) BabylonGovernor(_token, _timeLockAddress) {
        _votingDelay = votingDelay_;
        _votingPeriod = votingPeriod_;
    }

    function votingDelay() public view override returns (uint256) {
        return _votingDelay;
    }

    function votingPeriod() public view override returns (uint256) {
        return _votingPeriod;
    }
}
