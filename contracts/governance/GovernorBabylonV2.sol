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

pragma solidity 0.7.6;
pragma abicoder v2;

import { GovernorCompatibilityBravo } from './GovernorCompatibilityBravo.sol';
import { GovernorTimelockCompound } from './GovernorTimeLockCompound.sol';
import { Governor } from './Governor.sol';
import { SafeCast } from '../lib/SafeCast.sol';
import { Timers } from '../lib/Timers.sol';
import { ITimelock } from '../interfaces/ITimelock.sol';
import { IVoteToken } from '../interfaces/IVoteToken.sol';


contract GovernorBabylonV2 is GovernorCompatibilityBravo, GovernorTimelockCompound {
    
    using SafeCast for uint256;
    using Timers for Timers.BlockNumber;
    
    IVoteToken public immutable token;
    ITimelock public _timelock;
    
    mapping(uint256 => ProposalTimelock) private _proposalTimelocks;


    
    /**
     * @dev Sets the value for {name} and {version}
     */
    constructor(string memory _name, ITimelock _timeLockAddress, IVoteToken _token) Governor(_name) GovernorTimelockCompound(_timeLockAddress){
        token = _token;
    }
    
    /**
     * Read the voting weight from the token's built in snapshot mechanism (see {IGovernor-getVotes}).
     */
    function getVotes(address account, uint256 blockNumber) public view virtual override returns (uint256) {
        return token.getPriorVotes(account, blockNumber);
    }
    
    /**
     * GOVERNANCE FUNCTION. Allows to queue a specific proposal
     *
     * @notice Allows to queue a specific proposal of state succeeded
     * @param proposalId The ID of the proposal to queue
     */
    /**
     * @dev Function to queue a proposal to the timelock.
     */
    function queue(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public virtual override(GovernorCompatibilityBravo, GovernorTimelockCompound) returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        require(state(proposalId) == ProposalState.Succeeded, "Governor: proposal not successful");

        uint256 eta = block.timestamp + _timelock.delay();
        Timers.setDeadline(_proposalTimelocks[proposalId].timer, SafeCast.toUint64(eta));
        for (uint256 i = 0; i < targets.length; ++i) {
            require(
                !_timelock.queuedTransactions(keccak256(abi.encode(targets[i], values[i], "", calldatas[i], eta))),
                "GovernorTimelockCompound: identical proposal action already queued"
            );
            _timelock.queueTransaction(targets[i], values[i], "", calldatas[i], eta);
        }

        emit ProposalQueued(proposalId, eta);

        return proposalId;
    }
    
    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 /*descriptionHash*/
    ) internal virtual override(Governor, GovernorTimelockCompound) {
        uint256 eta = proposalEta(proposalId);
        require(eta > 0, "GovernorTimelockCompound: proposal not yet queued");
        for (uint256 i = 0; i < targets.length; ++i) {
            _timelock.executeTransaction{value: values[i]}(targets[i], values[i], "", calldatas[i], eta);
        }
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
    ) internal virtual override(Governor, GovernorTimelockCompound) returns (uint256) {
        uint256 proposalId = super._cancel(targets, values, calldatas, descriptionHash);

        uint256 eta = proposalEta(proposalId);
        if (eta > 0) {
            for (uint256 i = 0; i < targets.length; ++i) {
                _timelock.cancelTransaction(targets[i], values[i], "", calldatas[i], eta);
            }
            Timers.reset(_proposalTimelocks[proposalId].timer);
        }

        return proposalId;
    }
    
    /**
     * @dev Public accessor to check the eta of a queued proposal
     */
    function proposalEta(uint256 proposalId) public view virtual override(GovernorTimelockCompound, GovernorCompatibilityBravo) returns (uint256) {
        return Timers.getDeadline(_proposalTimelocks[proposalId].timer);
    }
    
     /**
     * @dev Address through which the governor executes action. In this case, the timelock.
     */
    function _executor() internal view virtual override(Governor, GovernorTimelockCompound) returns (address) {
        return address(_timelock);
    }
    
    /// @notice The number of votes required in order for a voter to become a proposer
    function proposalThreshold() public pure override returns (uint256) {
        return 10_000e18;
    } // 1% of BABL
    
    /// @notice The delay before voting on a proposal may take place, once proposed
    function votingDelay() public pure override returns (uint256) {
        return 1;
    } 

    /// @notice The duration of voting on a proposal, in blocks
    function votingPeriod() public pure override returns (uint256) {
        return 7 days;
    } 
    
    /**
     * @dev See {IGovernor-quorum}
     */
    function quorum(uint256 blockNumber) public view virtual override returns (uint256){
        return quorumVotes();
    }
    
     /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
    function quorumVotes() public pure override returns (uint256) {
        return 40_000e18;
    } // 4% of BABL


    
  
    
  

    
    


   
}