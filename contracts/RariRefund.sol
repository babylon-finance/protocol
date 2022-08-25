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
        uint256 _daiAmount,
        uint256 _usdcAmount,
        uint256 _wethAmount
    );

    /* ============ Constants ============ */

    // Tokens
    IWETH private constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    /* ============ Immutables ============ */

    IBabController private immutable controller;

    /* ============ State Variables ============ */

    mapping(address => uint256) public daiReimbursementAmount;
    mapping(address => uint256) public usdcReimbursementAmount;
    mapping(address => uint256) public wethReimbursementAmount;

    uint256 public totalDai;
    uint256 public totalUsdc;
    uint256 public totalWeth;

    uint256 public refundEnd;

    mapping(address => bool) public claimed;
    bool public claimOpen;

    /* ============ Initializer ============ */

    /**
     * Set controller and governor addresses
     *
     * @param _controller             Address of controller contract
     * @param _refundEnd               Timestamp when the reimbursement will end
     */
    constructor(IBabController _controller, uint256 _refundEnd) {
        _require(address(_controller) != address(0), Errors.ADDRESS_IS_ZERO);
        controller = _controller;
        refundEnd = _refundEnd;
    }

    /* ============ External Functions ============ */

    /**
     * Claims rari refund. Can only be done once per adddress
     *
     */
    function claimReimbursement() external {
        _require(claimOpen && block.timestamp <= refundEnd, Errors.CLAIM_OVER);
        _require(!claimed[msg.sender], Errors.ALREADY_CLAIMED);
        claimed[msg.sender] = true;
        uint256 daiAmount = daiReimbursementAmount[msg.sender];
        if (daiAmount > 0) {
            DAI.safeTransfer(msg.sender, daiAmount);
        }
        uint256 usdcAmount = usdcReimbursementAmount[msg.sender];
        if (usdcAmount > 0) {
            USDC.safeTransfer(msg.sender, usdcAmount);
        }
        uint256 wethAmount = wethReimbursementAmount[msg.sender];
        if (wethAmount > 0) {
            IERC20(address(WETH)).safeTransfer(msg.sender, wethAmount);
        }
        emit AmountClaimed(msg.sender, block.timestamp, daiAmount, usdcAmount, wethAmount);
    }

    /**
     * Sets the liquidation amount to split amongst all the whitelisted users.
     * @param _user Address of the user to reimburse
     * @param _daiAmount Amount of DAI to reimburse
     * @param _usdcAmount Amount of USDC to reimburse
     * @param _wethAmount Amount of WETH to reimburse
     */
    function setUserReimbursement(
        address _user,
        uint256 _daiAmount,
        uint256 _usdcAmount,
        uint256 _wethAmount
    ) external {
        controller.onlyGovernanceOrEmergency();
        totalDai = totalDai.sub(daiReimbursementAmount[_user]).add(_daiAmount);
        daiReimbursementAmount[_user] = _daiAmount;
        totalUsdc = totalUsdc.sub(usdcReimbursementAmount[_user]).add(_usdcAmount);
        usdcReimbursementAmount[_user] = _usdcAmount;
        totalWeth = totalWeth.sub(wethReimbursementAmount[_user]).add(_wethAmount);
        wethReimbursementAmount[_user] = _wethAmount;
    }

    /**
     * Starts reimbursement process
     */
    function startRefund() external {
        controller.onlyGovernanceOrEmergency();
        _require(
            DAI.balanceOf(address(this)) >= totalDai &&
                USDC.balanceOf(address(this)) >= totalUsdc &&
                WETH.balanceOf(address(this)) >= totalWeth,
            Errors.REFUND_TOKENS_NOT_SET
        );
        claimOpen = true;
    }

    /**
     * Recover any proceeds left after reimbursement is completed
     */
    function retrieveRemaining() external {
        controller.onlyGovernanceOrEmergency();
        _require(block.timestamp > refundEnd, Errors.CLAIM_NOT_OVER);
        DAI.safeTransfer(controller.EMERGENCY_OWNER(), DAI.balanceOf(address(this)));
        USDC.safeTransfer(controller.EMERGENCY_OWNER(), USDC.balanceOf(address(this)));
        IERC20(address(WETH)).safeTransfer(controller.EMERGENCY_OWNER(), WETH.balanceOf(address(this)));
    }
}
