// SPDX-License-Identifier: Apache-2.0



pragma solidity 0.8.9;
pragma abicoder v2;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';

import 'hardhat/console.sol';

import {IWETH} from '../interfaces/external/weth/IWETH.sol';
import {IHypervisor} from '../interfaces/IHypervisor.sol';
import {IBabController} from '../interfaces/IBabController.sol';

import {ControllerLib} from '../lib/ControllerLib.sol';

contract Assistant is OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using ControllerLib for IBabController;

    /* ============ Events ============ */
    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */
    /* ============ Constants ============ */

    /* ============ Constructor ============ */

    function initialize() public {
        OwnableUpgradeable.__Ownable_init();
    }

    /* ============ External Functions ============ */

    function startBondingProgram() external {
        IBabController controller = IBabController(0xD4a5b5fcB561dAF3aDF86F8477555B92FBa43b5F);

        require(msg.sender == controller.owner(), 'not valid sender');

        IERC20 BABL = IERC20(0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74);
        BABL.safeTransfer(controller.heart(), 11000e18);
    }

    /* ============ External Getter Functions ============ */
    /* ============ Internal Only Function ============ */

    // Can receive ETH
    // solhint-disable-next-line
    receive() external payable {}
}

contract AssistantV7 is Assistant {}
