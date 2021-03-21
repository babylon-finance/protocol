/*
    Copyright 2020 Babylon Finance.
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

pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ITimelock} from '../interfaces/ITimelock.sol';
import {IVoteToken} from '../interfaces/IVoteToken.sol';

contract GovernorAlpha is Ownable {
    /* ============ Events ============ */

    /// @notice An event emitted when a new proposal is created
    event ProposalCreated(
        uint256 id,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    /// @notice An event emitted when a vote has been cast on a proposal
    event VoteCast(address voter, uint256 proposalId, bool support, uint256 votes);

    /// @notice An event emitted when a proposal has been canceled
    event ProposalCanceled(uint256 id);

    /// @notice An event emitted when a proposal has been queued in the Timelock
    event ProposalQueued(uint256 id, uint256 eta);

    /// @notice An event emitted when a proposal has been executed in the Timelock
    event ProposalExecuted(uint256 id);

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    /// @notice The name of this contract
    string public constant name = 'BABL Governor Alpha';

    /// @notice The address of the BABL Protocol Timelock
    ITimelock public timelock;

    /// @notice The address of the BABL governance token
    IVoteToken public babl;

    /// @notice The address of the Governor Guardian
    address public guardian;

    /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
    function quorumVotes() public pure returns (uint256) {
        return 40_000e18;
    } // 4% of BABL

    /// @notice The number of votes required in order for a voter to become a proposer
    function proposalThreshold() public pure returns (uint256) {
        return 10_000e18;
    } // 1% of BABL

    /// @notice The maximum number of actions that can be included in a proposal
    function proposalMaxOperations() public pure returns (uint256) {
        return 10;
    } // 10 actions

    /// @notice The delay before voting on a proposal may take place, once proposed
    function votingDelay() public pure returns (uint256) {
        return 1;
    } // 1 block TODO - CHECK DELAY TO PROPOSE

    /// @notice The duration of voting on a proposal, in blocks
    function votingPeriod() public pure returns (uint256) {
        return 7 days;
    } // TODO - CHECK AND AGREE ON THE VOTING PERIOD

    /// @notice The total number of proposals
    uint256 public proposalCount;

    struct Proposal {
        // @notice Unique id for looking up a proposal
        uint256 id;
        // @notice Creator of the proposal
        address proposer;
        // @notice The timestamp that the proposal will be available for execution, set once the vote succeeds
        uint256 eta;
        // @notice the ordered list of target addresses for calls to be made
        address[] targets;
        // @notice The ordered list of values (i.e. msg.value) to be passed to the calls to be made
        uint256[] values;
        // @notice The ordered list of function signatures to be called
        string[] signatures;
        // @notice The ordered list of calldata to be passed to each call
        bytes[] calldatas;
        // @notice The block at which voting begins: holders must delegate their votes prior to this block
        uint256 startBlock;
        // @notice The block at which voting ends: votes must be cast prior to this block
        uint256 endBlock;
        // @notice Current number of votes in favor of this proposal
        uint256 forVotes;
        // @notice Current number of votes in opposition to this proposal
        uint256 againstVotes;
        // @notice Flag marking whether the proposal has been canceled
        bool canceled;
        // @notice Flag marking whether the proposal has been executed
        bool executed;
        // @notice Receipts of ballots for the entire set of voters
        mapping(address => Receipt) receipts;
    }

    /// @notice Ballot receipt record for a voter
    struct Receipt {
        // @notice Whether or not a vote has been cast
        bool hasVoted;
        // @notice Whether or not the voter supports the proposal
        bool support;
        // @notice The number of votes the voter had, which were cast
        uint96 votes;
    }

    /// @notice Possible states that a proposal may be in
    enum ProposalState {Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed}

    /// @notice The official record of all proposals ever proposed
    mapping(uint256 => Proposal) public proposals;

    /// @notice The latest proposal for each proposer
    mapping(address => uint256) public latestProposalIds;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256('EIP712Domain(string name,uint256 chainId,address verifyingContract)');

    /// @notice The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH = keccak256('Ballot(uint256 proposalId,bool support)');

    /* ============ Functions ============ */

    /* ============ Constructor ============ */

    /**
     * @notice Construct a GovernorAlpha and gives ownership to sender
     * @param timelock_ is the address of the timelock instance
     * @param babl_ is the instance of the BABL Token instance
     * @param guardian_ the Pause Guardian address capable of disabling protocol functionality. Used only in the event
     * of an unforeseen vulnerability.
     */

    constructor(
        address timelock_,
        address babl_,
        address guardian_
    ) {
        timelock = ITimelock(timelock_);
        babl = IVoteToken(babl_);
        guardian = guardian_;
    }

    /* ============ External Functions ============ */

    /* ===========  Token related Gov Functions ====== */

    /**
     * GOVERNANCE FUNCTION. Allows to propose governance actions
     *
     * @notice Propose new governance actions. Depends on power voting capacity of idea proposer
     * @param targets The array of addresses as destination targets
     * @param values The array of values
     * @param signatures The array of signatures
     * @param calldatas The array of calldatas to be executed as part of the proposals
     * @param description The description of the proposal
     * @return The proposal id created if it was successfully created
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) public returns (uint256) {
        require(
            babl.getPriorVotes(msg.sender, sub256(block.number, 1)) > proposalThreshold(),
            'GovernorAlpha::propose: proposer votes below proposal threshold'
        );
        require(
            targets.length == values.length &&
                targets.length == signatures.length &&
                targets.length == calldatas.length,
            'GovernorAlpha::propose: proposal function information arity mismatch'
        );
        require(targets.length != 0, 'GovernorAlpha::propose: must provide actions');
        require(targets.length <= proposalMaxOperations(), 'GovernorAlpha::propose: too many actions');

        uint256 latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
            ProposalState proposersLatestProposalState = state(latestProposalId);
            require(
                proposersLatestProposalState != ProposalState.Active,
                'GovernorAlpha::propose: one live proposal per proposer, found an already active proposal'
            );
            require(
                proposersLatestProposalState != ProposalState.Pending,
                'GovernorAlpha::propose: one live proposal per proposer, found an already pending proposal'
            );
        }

        uint256 startBlock = add256(block.number, votingDelay());
        uint256 endBlock = add256(startBlock, votingPeriod());

        proposalCount++;

        Proposal storage newProposal = proposals[proposalCount];
        newProposal.id = proposalCount;
        newProposal.proposer = msg.sender;
        newProposal.eta = 0;
        newProposal.targets = targets;
        newProposal.values = values;
        newProposal.signatures = signatures;
        newProposal.calldatas = calldatas;
        newProposal.startBlock = startBlock;
        newProposal.endBlock = endBlock;
        newProposal.forVotes = 0;
        newProposal.againstVotes = 0;
        newProposal.canceled = false;
        newProposal.executed = false;

        latestProposalIds[newProposal.proposer] = newProposal.id;

        emit ProposalCreated(
            newProposal.id,
            msg.sender,
            targets,
            values,
            signatures,
            calldatas,
            startBlock,
            endBlock,
            description
        );
        return newProposal.id;
    }

    /**
     * GOVERNANCE FUNCTION. Allows to queue a specific proposal
     *
     * @notice Allows to queue a specific proposal in state = Succeeded
     * @param proposalId The ID of the proposal
     */
    function queue(uint256 proposalId) public {
        require(
            state(proposalId) == ProposalState.Succeeded,
            'GovernorAlpha::queue: proposal can only be queued if it is succeeded'
        );
        Proposal storage proposal = proposals[proposalId];
        uint256 eta = add256(block.timestamp, timelock.delay());
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            _queueOrRevert(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], eta);
        }
        proposal.eta = eta;
        emit ProposalQueued(proposalId, eta);
    }

    /**
     * GOVERNANCE FUNCTION. Allows to queue or revert a transaction part of a proposal within the timelock
     *
     * @notice Allows to queue or revert a transaction part of a proposal (not queued earlier) within the timelock
     * @param target The addresses of the target
     * @param value The uint values
     * @param signature The signature
     * @param data The data
     * @param eta The timestamp of allowed execution
     */
    function _queueOrRevert(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) internal {
        require(
            !timelock.queuedTransactions(keccak256(abi.encode(target, value, signature, data, eta))),
            'GovernorAlpha::_queueOrRevert: proposal action already queued at eta'
        );
        timelock.queueTransaction(target, value, signature, data, eta);
    }

    /**
     * GOVERNANCE FUNCTION. Allows to execute a queued (state = queued) proposal
     *
     * @notice Allows to queue or revert a transaction part of a proposal (not queued earlier) within the timelock
     * @param proposalId The ID of the proposal
     */
    function execute(uint256 proposalId) public payable {
        require(
            state(proposalId) == ProposalState.Queued,
            'GovernorAlpha::execute: proposal can only be executed if it is queued'
        );
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            timelock.executeTransaction{value: (proposal.values[i])}(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                proposal.eta
            );
        }
        emit ProposalExecuted(proposalId);
    }

    /**
     * GOVERNANCE FUNCTION. Allows the msg.sender to cast a vote
     *
     * @notice Allows the msg.sender to cast a vote
     * @param proposalId The ID of the proposal
     * @param support Boolean whether it supports or not the proposal
     */
    function castVote(uint256 proposalId, bool support) public {
        return _castVote(msg.sender, proposalId, support);
    }

    /**
     * GOVERNANCE FUNCTION. Allows the cast of a vote by signature
     *
     * @notice Allows the cast of a vote by signature
     * @param proposalId The ID of the proposal
     * @param support Boolean whether it supports or not the proposal
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function castVoteBySig(
        uint256 proposalId,
        bool support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        bytes32 domainSeparator =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked('\x19\x01', domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), 'GovernorAlpha::castVoteBySig: invalid signature');
        return _castVote(signatory, proposalId, support);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows the Pause Guardian to cancel a proposal if state != executed
     *
     * @notice Allows the Pause Guardian to cancel a proposal if state != executed
     * @param proposalId The ID of the proposal
     */
    function cancel(uint256 proposalId) public {
        ProposalState _state = state(proposalId);
        require(_state != ProposalState.Executed, 'GovernorAlpha::cancel: cannot cancel executed proposal');

        Proposal storage proposal = proposals[proposalId];
        // A Pause Guardian is capable of disabling protocol functionality. Used only in the event of an unforeseen vulnerability and just for specific operations.
        require(
            msg.sender == guardian ||
                babl.getPriorVotes(proposal.proposer, sub256(block.number, 1)) < proposalThreshold(),
            'GovernorAlpha::cancel: proposer above threshold'
        );

        proposal.canceled = true;
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            timelock.cancelTransaction(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                proposal.eta
            );
        }

        emit ProposalCanceled(proposalId);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows the Pause Guardian to execute acceptAdmin in the timelock instance
     *
     * @notice Allows the Pause Guardian to execute acceptAdmin in the timelock instance
     */
    function __acceptAdmin() public {
        // The Pause Guardian is capable of disabling protocol functionality. Used only in the event of an unforeseen vulnerability and just for specific operations.
        require(msg.sender == guardian, 'GovernorAlpha::__acceptAdmin: sender must be gov guardian');
        timelock.acceptAdmin();
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows the Pause Guardian to abdicate as Guardian
     *
     * @notice Allows the Pause Guardian to abdicate as Guardian
     */
    function __abdicate() public {
        // The Pause Guardian is capable of disabling protocol functionality. Used only in the event of an unforeseen vulnerability and just for specific operations.
        require(msg.sender == guardian, 'GovernorAlpha::__abdicate: sender must be gov guardian');
        guardian = address(0);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows the Pause Guardian to queue a set of timelock pending admin
     *
     * @notice Allows the Pause Guardian to queue a set of timelock pending admin
     */
    function __queueSetTimelockPendingAdmin(address newPendingAdmin, uint256 eta) public {
        // The Pause Guardian is capable of disabling protocol functionality. Used only in the event of an unforeseen vulnerability and just for specific operations.
        require(msg.sender == guardian, 'GovernorAlpha::__queueSetTimelockPendingAdmin: sender must be gov guardian');
        timelock.queueTransaction(address(timelock), 0, 'setPendingAdmin(address)', abi.encode(newPendingAdmin), eta);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows the Pause Guardian to execute the set of timelock pending admin
     *
     * @notice Allows the Pause Guardian to execute the set of timelock pending admin
     */
    function __executeSetTimelockPendingAdmin(address newPendingAdmin, uint256 eta) public {
        // The Pause Guardian is capable of disabling protocol functionality. Used only in the event of an unforeseen vulnerability and just for specific operations.
        require(msg.sender == guardian, 'GovernorAlpha::__executeSetTimelockPendingAdmin: sender must be gov guardian');
        timelock.executeTransaction(address(timelock), 0, 'setPendingAdmin(address)', abi.encode(newPendingAdmin), eta);
    }

    /* ============ External Getter Functions ============ */

    /**
     * GOVERNANCE FUNCTION. Allows the caller to  check the list of actions of a proposal
     *
     * @notice Allows the caller to check the list of actions of a proposal
     * @param proposalId The ID of the proposal
     * @return targets of the proposalId
     * @return values of the proposalId
     * @return signatures of the proposalId
     * @return calldatas of the proposalId
     *
     */
    function getActions(uint256 proposalId)
        public
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        )
    {
        Proposal storage p = proposals[proposalId];
        return (p.targets, p.values, p.signatures, p.calldatas);
    }

    /**
     * GOVERNANCE FUNCTION. Allows the caller to get the receipt of the voter for a specific proposalId
     *
     * @notice Allows the caller to get the receipt of the voter for a specific proposalId
     * @param proposalId The ID of the proposal
     * @param voter The ID of the proposal
     * @return The receipt
     */
    function getReceipt(uint256 proposalId, address voter) public view returns (Receipt memory) {
        return proposals[proposalId].receipts[voter];
    }

    /**
     * GOVERNANCE FUNCTION. Allows the caller to get the state a specific proposalId
     *
     * @notice Allows the caller to get the state a specific proposalId
     * @return The proposal state
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId && proposalId > 0, 'GovernorAlpha::state: invalid proposal id');
        Proposal storage proposal = proposals[proposalId];
        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < quorumVotes()) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else if (block.timestamp >= add256(proposal.eta, timelock.GRACE_PERIOD())) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

    /* ============ Internal Only Function ============ */

    /**
     * GOVERNANCE FUNCTION. Allows the voter to cast a vote
     *
     * @dev Allows the voter to cast a vote
     * @param voter The address of the voter
     * @param proposalId The ID of the proposal
     * @param support Boolean whether it supports or not the proposal
     */
    function _castVote(
        address voter,
        uint256 proposalId,
        bool support
    ) internal {
        require(state(proposalId) == ProposalState.Active, 'GovernorAlpha::_castVote: voting is closed');
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[voter];
        require(receipt.hasVoted == false, 'GovernorAlpha::_castVote: voter already voted');
        uint96 votes = babl.getPriorVotes(voter, proposal.startBlock);

        if (support) {
            proposal.forVotes = add256(proposal.forVotes, votes);
        } else {
            proposal.againstVotes = add256(proposal.againstVotes, votes);
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        emit VoteCast(voter, proposalId, support, votes);
    }

    /**
     * INTERNAL SAFE MATH FUNCTION. Safe add two uint256 values checking overflow returning uint
     *
     * @dev Safe add two uint256 values checking overflow
     */
    function add256(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, 'addition overflow');
        return c;
    }

    /**
     * INTERNAL SAFE MATH FUNCTION. Safe sub two uint256 values checking underflow returning uint
     *
     * @dev Safe sub two uint256 values checking overflow
     */
    function sub256(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, 'subtraction underflow');
        return a - b;
    }

    /**
     * INTERNAL FUNCTION. Internal function to get chain ID
     *
     * @dev internal function to get chain ID
     */
    function getChainId() internal pure returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}
