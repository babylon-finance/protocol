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

    mapping(uint256 => bytes32) private _timelockIds;
    mapping(uint256 => ProposalDetails) private _proposalDetails;
    mapping(uint256 => ProposalCore) private _proposals;
    TimelockController private _timelock;

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
        return propose(targets, values, new string[](calldatas.length), calldatas, description);
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
        require(
            getVotes(msg.sender, block.number - 1) >= proposalThreshold(),
            'GovernorCompatibilityBravo: proposer votes below proposal threshold'
        );

        uint256 proposalId = super.propose(targets, values, _encodeCalldata(signatures, calldatas), description);
        _storeProposal(proposalId, _msgSender(), targets, values, signatures, calldatas, description);
        return proposalId;
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
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        require(state(proposalId) == ProposalState.Succeeded, 'Governor: proposal not successful');

        uint256 delay = _timelock.getMinDelay();
        _timelockIds[proposalId] = _timelock.hashOperationBatch(targets, values, calldatas, 0, descriptionHash);
        _timelock.scheduleBatch(targets, values, calldatas, 0, descriptionHash, delay);

        emit ProposalQueued(proposalId, block.timestamp + delay);

        return proposalId;
    }

    /**
     * @dev See {IGovernorCompatibilityBravo-queue}.
     */
    function queue(uint256 proposalId) public virtual override {
        ProposalDetails storage details = _proposalDetails[proposalId];
        queue(
            details.targets,
            details.values,
            _encodeCalldata(details.signatures, details.calldatas),
            details.descriptionHash
        );
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
        uint256 eta = _timelock.getTimestamp(_timelockIds[proposalId]);
        return eta == 1 ? 0 : eta; // _DONE_TIMESTAMP (1) should be replaced with a 0 value
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
        ProposalState status = super.state(proposalId);

        if (status != ProposalState.Succeeded) {
            return status;
        }

        // core tracks execution, so we just have to check if successful proposal have been queued.
        bytes32 queueid = _timelockIds[proposalId];
        if (queueid == bytes32(0)) {
            return status;
        } else if (_timelock.isOperationDone(queueid)) {
            return ProposalState.Executed;
        } else {
            return ProposalState.Queued;
        }
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
        uint256, /* proposalId */
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override(Governor, GovernorTimelockControl) {
        _timelock.executeBatch{value: msg.value}(targets, values, calldatas, 0, descriptionHash);
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
        uint256 proposalId = super._cancel(targets, values, calldatas, descriptionHash);

        if (_timelockIds[proposalId] != 0) {
            _timelock.cancel(_timelockIds[proposalId]);
            delete _timelockIds[proposalId];
        }

        return proposalId;
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
        ProposalDetails storage details = _proposalDetails[proposalId];

        details.proposer = proposer;
        details.targets = targets;
        details.values = values;
        details.signatures = signatures;
        details.calldatas = calldatas;
        details.descriptionHash = keccak256(bytes(description));
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
        ProposalDetails storage details = _proposalDetails[proposalId];
        return quorum(proposalSnapshot(proposalId)) < details.forVotes;
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
        ProposalDetails storage details = _proposalDetails[proposalId];
        return details.forVotes > details.againstVotes;
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
        ProposalCore storage proposal = _proposals[proposalId];
        require(state(proposalId) == ProposalState.Active, 'Governor: vote not currently active');

        uint256 weight = getVotes(account, proposal.voteStart.getDeadline());
        _countVote(proposalId, account, support, weight);

        emit VoteCast(account, proposalId, support, weight, reason);

        return weight;
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
        ProposalDetails storage details = _proposalDetails[proposalId];
        Receipt storage receipt = details.receipts[account];

        require(!receipt.hasVoted, 'GovernorCompatibilityBravo: vote already casted');
        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = SafeCast.toUint96(weight);

        if (support == uint8(VoteType.Against)) {
            details.againstVotes += weight;
        } else if (support == uint8(VoteType.For)) {
            details.forVotes += weight;
        } else if (support == uint8(VoteType.Abstain)) {
            details.abstainVotes += weight;
        } else {
            revert('GovernorCompatibilityBravo: invalid vote type');
        }
    }

    /**
     * @dev Address through which the governor executes action. In this case, the timelock.
     */
    function _executor() internal view virtual override(Governor, GovernorTimelockControl) returns (address) {
        return address(_timelock);
    }

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
