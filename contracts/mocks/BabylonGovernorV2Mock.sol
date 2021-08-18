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

import "contracts-next/governance/Governor.sol";
import "contracts-next/governance/extensions/GovernorProposalThreshold.sol";
import "contracts-next/governance/extensions/GovernorCountingSimple.sol";
import "contracts-next/governance/extensions/GovernorVotesComp.sol";
import "contracts-next/governance/extensions/GovernorTimelockControl.sol";

import {BabylonGovernor} from '../governance/BabylonGovernor.sol';

contract BabylonGovernorV2 is BabylonGovernor {
    uint256 public answer;

    /* ============ Constructor ============ */

    /**
     * @dev Sets the value for {name} and {version}
     */
    constructor(
        ERC20VotesComp _token,
        TimelockController _timeLockAddress
    ) BabylonGovernor(_token, _timeLockAddress) {
        answer = 42;
    }
}
