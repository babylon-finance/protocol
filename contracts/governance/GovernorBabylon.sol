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

import 'hardhat/console.sol';

import {GovernorCompatibilityBravo} from './GovernorCompatibilityBravo.sol';
import {GovernorTimelockControl} from './GovernorTimelockControl.sol';
import {TimelockController} from './TimelockController.sol';
import {GovernorVotesComp} from './GovernorVotesComp.sol';
import {Governor} from './Governor.sol';

import {SafeCast} from '../.deps/npm/@openzeppelin/contracts/utils/math/SafeCast.sol';
import {AccessControl} from '../.deps/npm/@openzeppelin/contracts/access/AccessControl.sol';
import {ECDSA} from '../.deps/npm/@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '../.deps/npm/@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol';
import {ERC165} from '../.deps/npm/@openzeppelin/contracts/utils/introspection/ERC165.sol';
import {IERC165} from '../.deps/npm/@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {Context} from '../.deps/npm/@openzeppelin/contracts/utils/Context.sol';
import {Counters} from '../.deps/npm/@openzeppelin/contracts/utils/Counters.sol';
import {Strings} from '../.deps/npm/@openzeppelin/contracts/utils/Strings.sol';
import {SafeMath} from '../.deps/npm/@openzeppelin/contracts/utils/math/SafeMath.sol';
import {Address} from '../.deps/npm/@openzeppelin/contracts/utils/Address.sol';
import {Timers} from '../.deps/npm/@openzeppelin/contracts/utils/Timers.sol';
import {ERC20VotesComp} from '../.deps/npm/@openzeppelin/contracts/token/ERC20/extensions/ERC20VotesComp.sol';

import {IGovernorTimelock} from '../interfaces/IGovernorTimelock.sol';
import {IGovernorCompatibilityBravo} from '../interfaces/IGovernorCompatibilityBravo.sol';
import {IGovernor} from '../interfaces/IGovernor.sol';

contract GovernorBabylon is GovernorCompatibilityBravo, GovernorTimelockControl, GovernorVotesComp {
    using SafeCast for uint256;
    using SafeMath for uint256;
    using Timers for Timers.BlockNumber;

    /* ============ Modifiers ================= */

    /* ============ State Variables ============ */

    /* ============ Functions ============ */

    /* ============ Constructor ============ */

    /**
     * @dev Sets the value for {name} and {version}
     */
    constructor(
        string memory _name,
        TimelockController _timeLockAddress,
        ERC20VotesComp _token
    ) Governor(_name) GovernorTimelockControl(_timeLockAddress) GovernorVotesComp(_token) {}

    /* ============ External Functions ============ */

    /**
     * @dev See {IGovernor-propose}.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override(IGovernor, Governor, GovernorCompatibilityBravo) returns (uint256) {
        return super.propose(targets, values, calldatas, description);
    }

    /**
     * @dev See {IGovernorCompatibilityBravo-propose}.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override returns (uint256) {
        return super.propose(targets, values, signatures, calldatas, description);
    }

    /**
     * @dev Function to queue a proposal to the timelock.
     */
    function queue(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public virtual override(GovernorCompatibilityBravo, GovernorTimelockControl) returns (uint256) {
        return super.queue(targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev See {IGovernorCompatibilityBravo-queue}.
     */
    function queue(uint256 proposalId) public virtual override {
        return super.queue(proposalId);
    }

    /* ============ View Functions ============ */

    /**
     * @dev Public accessor to check the eta of a queued proposal
     */
    function proposalEta(uint256 proposalId)
        public
        view
        virtual
        override(GovernorCompatibilityBravo, GovernorTimelockControl)
        returns (uint256)
    {
        return super.proposalEta(proposalId);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, Governor, GovernorTimelockControl)
        returns (bool)
    {
        return interfaceId == type(IGovernorTimelock).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Overriden version of the {Governor-state} function with added support for the `Queued` status.
     */
    function state(uint256 proposalId)
        public
        view
        virtual
        override(IGovernor, Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    /// @notice The number of votes required in order for a voter to become a proposer
    function proposalThreshold() public view override returns (uint256) {
        return 5_000e18;
    } // 0.5% of BABL

    /// @notice The delay before voting on a proposal may take place, once proposed
    function votingDelay() public pure override(Governor, IGovernor) returns (uint256) {
        return 4;
    }

    /// @notice The duration of voting on a proposal, in blocks
    function votingPeriod() public pure override(Governor, IGovernor) returns (uint256) {
        return 7 days;
    }

    /**
     * @dev See {IGovernor-quorum}
     */
    function quorum(uint256 blockNumber) public view virtual override(Governor, IGovernor) returns (uint256) {
        return quorumVotes();
    }

    /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
    function quorumVotes() public view override returns (uint256) {
        return 40_000e18;
    } // 4% of BABL

    /* ============ Internal Functions ============ */

    /**
     * @dev Overriden execute function that run the already queued proposal through the timelock.
     */
    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override(Governor, GovernorTimelockControl) {
        GovernorTimelockControl._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev Overriden version of the {Governor-_cancel} function to cancel the timelocked proposal if it has already
     * been queued.
     */
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev Store proposal metadata for later lookup
     */
    function _storeProposal(
        uint256 proposalId,
        address proposer,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) internal virtual override {
        return super._storeProposal(proposalId, proposer, targets, values, signatures, calldatas, description);
    }

    /**
     * @dev See {Governor-_quorumReached}. In this module, only forVotes count toward the quorum.
     */
    function _quorumReached(uint256 proposalId)
        internal
        view
        virtual
        override(GovernorCompatibilityBravo, Governor)
        returns (bool)
    {
        return super._quorumReached(proposalId);
    }

    /**
     * @dev See {Governor-_voteSucceeded}. In this module, the forVotes must be scritly over the againstVotes.
     */
    function _voteSucceeded(uint256 proposalId)
        internal
        view
        virtual
        override(GovernorCompatibilityBravo, Governor)
        returns (bool)
    {
        return super._voteSucceeded(proposalId);
    }

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been casted yet, retrieve
     * voting weight using {IGovernor-getVotes} and call the {_countVote} internal function.
     *
     * Emits a {IGovernor-VoteCast} event.
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason
    ) internal virtual override returns (uint256) {
        return super._castVote(proposalId, account, support, reason);
    }

    /**
     * @dev See {Governor-_countVote}. In this module, the support follows Governor Bravo.
     */
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight
    ) internal virtual override(GovernorCompatibilityBravo, Governor) {
        return super._countVote(proposalId, account, support, weight);
    }

    /**
     * @dev Address through which the governor executes action. In this case, the timelock.
     */
    function _executor() internal view virtual override(Governor, GovernorTimelockControl) returns (address) {
        return GovernorTimelockControl._executor();
    }
}
