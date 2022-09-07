// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import {PreciseUnitMath} from './lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from './lib/SafeDecimalMath.sol';
import {LowGasSafeMath as SafeMath} from './lib/LowGasSafeMath.sol';
import {Errors, _require, _revert} from './lib/BabylonErrors.sol';
import {ControllerLib} from './lib/ControllerLib.sol';
import {IBabController} from './interfaces/IBabController.sol';
import 'hardhat/console.sol';

import {VoteToken} from './token/VoteToken.sol';
import {TimeLockedToken} from './token/TimeLockedToken.sol';

/**
 * @title Liquidation
 * @author Babylon Finance
 *
 * Contract that performs the liquidation process
 *
 */
contract Liquidation {
    using SafeERC20 for IERC20;
    using PreciseUnitMath for uint256;
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;
    using ControllerLib for IBabController;

    /* ============ Modifiers ============ */

    /* ============ Events ============ */

    event AmountClaimed(address _user, uint256 _timestamp, uint256 _amount);

    /* ============ Constants ============ */

    // Tokens
    IERC20 private constant BABL = IERC20(0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74);
    IERC20 private constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    /* ============ Immutables ============ */

    IBabController private immutable controller;

    /* ============ State Variables ============ */
    uint256 public totalWhitelistAmount;
    uint256 public liquidationAmount;
    mapping(address => uint256) public whitelistAmounts;
    mapping(address => uint256) public claimedAmounts;
    mapping(address => uint256) public BABLAtSnapshot;

    uint256 public whitelistEnd;
    uint256 public claimEnd;
    uint256 public snapshotBlockNumber;

    /* ============ Initializer ============ */

    /**
     * Set controller and governor addresses
     *
     * @param _controller             Address of controller contract
     * @param _whitelistEnd           Timestamp when the whitelist will end
     * @param _claimEnd               Timestamp when the claim will end
     */
    constructor(
        IBabController _controller,
        uint256 _whitelistEnd,
        uint256 _claimEnd
    ) {
        _require(address(_controller) != address(0), Errors.ADDRESS_IS_ZERO);
        controller = _controller;
        whitelistEnd = _whitelistEnd;
        claimEnd = _claimEnd;
    }

    /* ============ External Functions ============ */

    /**
     * Adds user to the whitelist. Can only be done once per address.
     *
     */
    function addToWhitelist() external {
        _require(block.timestamp <= whitelistEnd, Errors.WHITELIST_OVER);
        _require(whitelistAmounts[msg.sender] == 0, Errors.ALREADY_WHITELISTED);
        _require(snapshotBlockNumber > 0 && BABLAtSnapshot[msg.sender] > 0, Errors.NO_BALANCE_WHITELIST);
        whitelistAmounts[msg.sender] = BABLAtSnapshot[msg.sender];
        totalWhitelistAmount = totalWhitelistAmount.add(BABLAtSnapshot[msg.sender]);
    }

    /**
     * Claims user liquidation proceeeds. Can only be done once per adddress
     *
     */
    function claimProceeds() external {
        _require(block.timestamp > whitelistEnd && block.timestamp < claimEnd, Errors.CLAIM_OVER);
        _require(whitelistAmounts[msg.sender] > 0, Errors.NOT_WHITELISTED);
        _require(claimedAmounts[msg.sender] == 0, Errors.ALREADY_CLAIMED);
        _require(liquidationAmount > 0, Errors.LIQUIDATION_AMOUNT_NOT_SET);
        uint256 userAmount = liquidationAmount.mul(whitelistAmounts[msg.sender]).div(totalWhitelistAmount);
        claimedAmounts[msg.sender] = whitelistAmounts[msg.sender];
        DAI.safeTransfer(msg.sender, userAmount);
        emit AmountClaimed(msg.sender, block.timestamp, userAmount);
    }

    /**
     * Sets the liquidation amount to split amongst all the whitelisted users.
     * @param _liquidationAmount Total Amount of DAI to split amongst liquidators
     */
    function setGlobalLiquidationAmount(uint256 _liquidationAmount) external {
        controller.onlyGovernanceOrEmergency();
        liquidationAmount = _liquidationAmount;
        require(DAI.balanceOf(address(this)) >= _liquidationAmount, 'Not enough DAI');
    }

    /**
     * Updates whitelist end date
     * @param _whitelistEnd      Whitelist end date
     */
    function setWhitelistEnd(uint256 _whitelistEnd) external {
        controller.onlyGovernanceOrEmergency();
        whitelistEnd = _whitelistEnd;
    }

    /**
     * Updates claim end date
     * @param _claimEnd             Claim end date
     */
    function setClaimEnd(uint256 _claimEnd) external {
        controller.onlyGovernanceOrEmergency();
        claimEnd = _claimEnd;
    }

    /**
     * Fetches the unlocked balances of all BABL holders
     * @param _users            List of user addresses
     */
    function setSnapshotBlockNumber(address[] calldata _users) external {
        require(msg.sender == 0x97FcC2Ae862D03143b393e9fA73A32b563d57A6e || msg.sender == 0x08839d766B1381014868eB0C3aa1C64db2B02326, 'No permission');
        for (uint256 i = 0; i < _users.length; i++) {
            BABLAtSnapshot[_users[i]] = TimeLockedToken(address(BABL)).unlockedBalance(_users[i]);
        }
        snapshotBlockNumber = block.number;
    }

    /**
     * Recover any proceeds left after liquidation process is completed
     */
    function retrieveRemaining() external {
        controller.onlyGovernanceOrEmergency();
        _require(block.timestamp > claimEnd, Errors.CLAIM_NOT_OVER);
        DAI.safeTransfer(msg.sender, DAI.balanceOf(address(this)));
    }
}
