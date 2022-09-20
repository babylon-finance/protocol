// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IWETH} from './interfaces/external/weth/IWETH.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import {PreciseUnitMath} from './lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from './lib/SafeDecimalMath.sol';
import {LowGasSafeMath as SafeMath} from './lib/LowGasSafeMath.sol';
import {Errors, _require, _revert} from './lib/BabylonErrors.sol';
import {ControllerLib} from './lib/ControllerLib.sol';

import {IBabController} from './interfaces/IBabController.sol';

/**
 * @title RariRefund
 * @author Babylon Finance
 *
 * Contract that refunds Rari users for the hack
 *
 */
contract RariRefund {
    using SafeERC20 for IERC20;
    using PreciseUnitMath for uint256;
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;
    using ControllerLib for IBabController;

    /* ============ Modifiers ============ */

    /* ============ Events ============ */

    event AmountClaimed(
        address _user,
        uint256 _timestamp,
        uint256 _daiAmount
    );

    /* ============ Constants ============ */

    // Tokens
    IERC20 private constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    /* ============ Immutables ============ */

    IBabController private immutable controller;

    /* ============ State Variables ============ */

    mapping(address => uint256) public daiReimbursementAmount;
    mapping(address => bool) public claimed;

    uint256 public totalDai;
    bool public claimOpen;

    /* ============ Initializer ============ */

    /**
     * Set controller and governor addresses
     *
     * @param _controller             Address of controller contract
     */
    constructor(IBabController _controller) {
        _require(address(_controller) != address(0), Errors.ADDRESS_IS_ZERO);
        controller = _controller;
    }

    /* ============ External Functions ============ */

    /**
     * Claims rari refund. Can only be done once per adddress
     *
     */
    function claimReimbursement() external {
        _require(claimOpen, Errors.CLAIM_OVER);
        uint256 daiAmount = daiReimbursementAmount[msg.sender];
        _require(!claimed[msg.sender] && daiAmount > 0, Errors.ALREADY_CLAIMED);
        claimed[msg.sender] = true;
        DAI.safeTransfer(msg.sender, daiAmount);
        emit AmountClaimed(msg.sender, block.timestamp, daiAmount);
    }

    /**
     * Sets the liquidation amount to split amongst all the whitelisted users.
     * @param _user Address of the user to reimburse
     * @param _daiAmount Amount of DAI to reimburse
     */
    function setUserReimbursement(
        address _user,
        uint256 _daiAmount
    ) external {
        controller.onlyGovernanceOrEmergency();
        totalDai = totalDai.sub(daiReimbursementAmount[_user]).add(_daiAmount);
        daiReimbursementAmount[_user] = _daiAmount;
    }

    /**
     * Starts reimbursement process
     */
    function startRefund() external {
        controller.onlyGovernanceOrEmergency();
        _require(
            DAI.balanceOf(address(this)) >= totalDai,
            Errors.REFUND_TOKENS_NOT_SET
        );
        claimOpen = true;
    }
}
