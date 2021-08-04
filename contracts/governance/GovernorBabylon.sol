/*
    Copyright 2021 Babylon Finance.
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity ^0.8.0;

import {GovernorCompatibilityBravo} from './GovernorCompatibilityBravo.sol';
import {GovernorTimelockControl} from './GovernorTimelockControl.sol';
import {TimelockController} from './TimelockController.sol';
import {GovernorVotesComp } from './GovernorVotesComp.sol';
import {Governor} from './Governor.sol';
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {IGovernorTimelock} from '../interfaces/IGovernorTimelock.sol';
import {IGovernorCompatibilityBravo} from '../interfaces/IGovernorCompatibilityBravo.sol';


import "../lib/Address.sol";

import {Timers} from '../lib/Timers.sol';
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20VotesComp.sol";
import {IGovernor} from '../interfaces/IGovernor.sol';

contract GovernorBabylon is GovernorCompatibilityBravo, GovernorTimelockControl, GovernorVotesComp {
    using SafeCast for uint256;
    using Timers for Timers.BlockNumber;
   
    struct ProposalTimelock {
        Timers.Timestamp timer;
    }

    mapping(uint256 => ProposalTimelock) private _proposalTimelocks;
    mapping(uint256 => bytes32) private _timelockIds;
    mapping(uint256 => ProposalDetails) private _proposalDetails;

    TimelockController private _timelock;

    /**
     * @dev Sets the value for {name} and {version}
     */
    constructor(
        string memory _name,
        TimelockController _timeLockAddress,
        ERC20VotesComp _token
    ) Governor(_name) GovernorTimelockControl(_timeLockAddress) GovernorVotesComp(_token) {
        token = _token;
    }



    /**
     * @dev Public accessor to check the eta of a queued proposal
     */
    function proposalEta(uint256 proposalId)
        public
        view
        virtual
        override(GovernorTimelockControl, GovernorCompatibilityBravo)
        returns (uint256)
    {
        return Timers.getDeadline(_proposalTimelocks[proposalId].timer);
    }

    /**
     * @dev Overriden execute function that run the already queued proposal through the timelock.
     */
    function _execute(
        uint256, /* proposalId */
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override(Governor, GovernorTimelockControl) {
        _timelock.executeBatch{value: msg.value}(targets, values, calldatas, 0, descriptionHash);
    }

    /**
     * @dev Overriden version of the {Governor-_cancel} function to cancel the timelocked proposal if it as already
     * been queued.
     */
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override(Governor,GovernorTimelockControl) returns (uint256) {
        uint256 proposalId = super._cancel(targets, values, calldatas, descriptionHash);

        if (_timelockIds[proposalId] != 0) {
            _timelock.cancel(_timelockIds[proposalId]);
            delete _timelockIds[proposalId];
        }

        return proposalId;
    }

    /**
     * @dev See {IGovernorCompatibilityBravo-queue}.
     */
    function queue(uint256 proposalId) public virtual override(GovernorTimelockControl, GovernorCompatibilityBravo) {
        ProposalDetails storage details = _proposalDetails[proposalId];
        queue(
            details.targets,
            details.values,
            _encodeCalldata(details.signatures, details.calldatas),
            details.descriptionHash
        );
    }
     /**
     * @dev Address through which the governor executes action. In this case, the timelock.
     */
    function _executor() internal view virtual override(Governor,GovernorTimelockControl) returns (address) {
        return address(_timelock);
    }

    /// @notice The number of votes required in order for a voter to become a proposer
    function proposalThreshold() public pure override returns (uint256) {
        return 10_000e18;
    } // 1% of BABL

    /// @notice The delay before voting on a proposal may take place, once proposed
    function votingDelay() public pure override(Governor,IGovernor) returns (uint256) {
        return 1;
    }

    /// @notice The duration of voting on a proposal, in blocks
    function votingPeriod() public pure override(Governor,IGovernor) returns (uint256) {
        return 7 days;
    }

    /**
     * @dev See {IGovernor-quorum}
     */
    function quorum(uint256 blockNumber) public view virtual override(Governor,IGovernor) returns (uint256) {
        return quorumVotes();
    }

    /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
    function quorumVotes() public pure override returns (uint256) {
        return 40_000e18;
    } // 4% of BABL

      /**
     * @dev Encodes calldatas with optional function signature.
     */
    function _encodeCalldata(string[] memory signatures, bytes[] memory calldatas)
        internal
        pure
        override
        returns (bytes[] memory)
    {
        bytes[] memory fullcalldatas = new bytes[](calldatas.length);

        for (uint256 i = 0; i < signatures.length; ++i) {
            fullcalldatas[i] = bytes(signatures[i]).length == 0
                ? calldatas[i]
                : abi.encodePacked(bytes4(keccak256(bytes(signatures[i]))), calldatas[i]);
        }

        return fullcalldatas;
    }
}
