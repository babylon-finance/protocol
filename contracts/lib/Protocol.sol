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

import {Errors, _require, _revert} from './BabylonErrors.sol';

import {IBabController} from '../interfaces/IBabController.sol';

library Protocol {
    function onlyGovernanceOrEmergency(IBabController controller) internal {
        _require(
            msg.sender == controller.owner() || msg.sender == controller.EMERGENCY_OWNER(),
            Errors.ONLY_GOVERNANCE_OR_EMERGENCY
        );
    }
}
