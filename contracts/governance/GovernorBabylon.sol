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

import { Governor } from './Governor.sol';
import { IGovernor } from '../interfaces/IGovernor.sol';
import { IVoteToken } from '../interfaces/IVoteToken.sol';

contract GovernorBabylon is IGovernor, Governor {
    
    IVoteToken public immutable token;
    
    /**
     * @dev Sets the value for {name} and {version}
     */
    constructor(string memory _name, IVoteToken _token) Governor(_name) {
        token = _token;
    }
    
    function COUNTING_MODE() public pure virtual override returns (string memory)  {
        return COUNTING_MODE();
    }
    
    function hasVoted(uint256 proposalId, address account) public view virtual override returns (bool) {
        return hasVoted(proposalId, account);
    }
    
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight
    ) internal virtual override {
        _countVote(proposalId, account, support, weight);
    }
    
    function _quorumReached(uint256 proposalId) internal view virtual override returns (bool) {

        return
            _quorumReached(proposalId);
    }
    
    function _voteSucceeded(uint256 proposalId) internal view virtual override returns (bool) {
        return _voteSucceeded(proposalId);
    }
    
    function quorum(uint256 blockNumber) public view virtual override(IGovernor, Governor) returns (uint256){
        
    }
    
     /**
     * @dev See {IGovernor-votingDelay}
     */
    function votingDelay() public view virtual override(IGovernor, Governor) returns (uint256){
    }

    /**
     * @dev See {IGovernor-votingPeriod}
     */
    function votingPeriod() public view virtual override(IGovernor, Governor) returns (uint256){
    }
    
    /**
     * Read the voting weight from the token's built in snapshot mechanism (see {IGovernor-getVotes}).
     */
    function getVotes(address account, uint256 blockNumber) public view virtual override(IGovernor, Governor) returns (uint256) {
        return token.getPriorVotes(account, blockNumber);
    }


   
}