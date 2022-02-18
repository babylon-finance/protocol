/*
    Copyright 2021 Babylon Finance

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

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {IWETH} from '../interfaces/external/weth/IWETH.sol';
import {IHypervisor} from '../interfaces/IHypervisor.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {ControllerLib} from '../lib/ControllerLib.sol';

contract Assistant is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    /* ============ Events ============ */
    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */
    /* ============ Constants ============ */

    IBabController controller = IBabController(0xD4a5b5fcB561dAF3aDF86F8477555B92FBa43b5F);

    /* ============ Constructor ============ */

    function initialize() public {
        OwnableUpgradeable.__Ownable_init();
    }

    /* ============ External Functions ============ */

    function startBondingProgram() external {
        controller.onlyGovernanceOrEmergency();
        IERC20 BABL = IERC20(0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74);
        BABL.safeTransfer(controller.heart(), 11000e18);
    }

    /* ============ External Getter Functions ============ */
    /* ============ Internal Only Function ============ */

    // Can receive ETH
    // solhint-disable-next-line
    receive() external payable {}
}

contract AssistantV4 is Assistant {}
