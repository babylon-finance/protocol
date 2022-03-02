// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.5;

import '@openzeppelin/contracts/governance/Governor.sol';
import '@openzeppelin/contracts/governance/compatibility/GovernorCompatibilityBravo.sol';
import '@openzeppelin/contracts/governance/extensions/GovernorVotesComp.sol';
import '@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol';

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
