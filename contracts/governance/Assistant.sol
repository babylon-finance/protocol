// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';

import {IWETH} from '../interfaces/external/weth/IWETH.sol';
import {IHypervisor} from '../interfaces/IHypervisor.sol';
import {IBabController} from '../interfaces/IBabController.sol';

import {ControllerLib} from '../lib/ControllerLib.sol';
import {LowGasSafeMath} from '../lib/LowGasSafeMath.sol';

import 'hardhat/console.sol';

contract Assistant is OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using ControllerLib for IBabController;
    using LowGasSafeMath for uint256;

    /* ============ Events ============ */
    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */
    /* ============ Constants ============ */

    /* ============ Constructor ============ */

    function initialize() public {
        OwnableUpgradeable.__Ownable_init();
    }

    /* ============ External Functions ============ */

    // We need to send total BABL to assistant first
    function rewardProphets(address[] calldata _addresses) external {
        uint256 bablPerProphet = 2e18;
        require(address(msg.sender) == 0x97FcC2Ae862D03143b393e9fA73A32b563d57A6e, 'Only multisig');
        IERC20 BABL = IERC20(0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74);
        uint256 length = _addresses.length;
        require(BABL.balanceOf(address(this)) >= length.mul(bablPerProphet), 'Not enough BABL');
        for (uint256 i = 0; i < length; i++) {
            BABL.safeTransfer(_addresses[i], bablPerProphet);
        }
    }

    /* ============ External Getter Functions ============ */
    /* ============ Internal Only Function ============ */

    // Can receive ETH
    // solhint-disable-next-line
    receive() external payable {}
}

contract AssistantV8 is Assistant {}
