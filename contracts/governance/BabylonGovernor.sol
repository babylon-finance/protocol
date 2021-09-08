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

pragma solidity ^0.8.2;

import 'hardhat/console.sol';

import 'contracts-next/governance/Governor.sol';
import 'contracts-next/governance/compatibility/GovernorCompatibilityBravo.sol';
import 'contracts-next/governance/extensions/GovernorVotesComp.sol';
import 'contracts-next/governance/extensions/GovernorTimelockControl.sol';

contract BabylonGovernor is Governor, GovernorCompatibilityBravo, GovernorVotesComp, GovernorTimelockControl {
    constructor(ERC20VotesComp _token, TimelockController _timelock)
        Governor('BabylonGovernor')
        GovernorVotesComp(_token)
        GovernorTimelockControl(_timelock)
    {}

    function votingDelay() public view virtual override returns (uint256) {
        return 1; // 1 block
    }

    function votingPeriod() public view virtual override returns (uint256) {
        return 45818; // 1 week
    }

    function quorum(
        uint256 /* blockNumber */
    ) public pure override returns (uint256) {
        return 40_000e18;
    }

    function proposalThreshold() public pure override returns (uint256) {
        return 5_000e18;
    }

    // The following functions are overrides required by Solidity.

    function getVotes(address account, uint256 blockNumber)
        public
        view
        override(IGovernor, GovernorVotesComp)
        returns (uint256)
    {
        return super.getVotes(account, blockNumber);
    }

    function state(uint256 proposalId)
        public
        view
        override(Governor, IGovernor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor, GovernorCompatibilityBravo, IGovernor) returns (uint256) {
        return super.propose(targets, values, calldatas, description);
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(Governor, IERC165, GovernorTimelockControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
