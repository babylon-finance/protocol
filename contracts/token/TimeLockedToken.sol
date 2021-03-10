/*
    Copyright 2020 Babylon Finance.

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


pragma solidity 0.7.4;

import "hardhat/console.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { VoteToken } from "./VoteToken.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TimeLockedToken
 * @notice Time Locked ERC20 Token
 * @author Babylon Finance modified a version of TimeLockedToken provided by Harold Hyatt
 * @dev Contract which gives the ability to time-lock tokens
 *
 * By overriding the balanceOf(), transfer(), and transferFrom()
 * functions in ERC20, an account can show its full, post-distribution
 * balance but only transfer or spend up to an allowed amount
 *
 * Every time an epoch passes, a portion of previously non-spendable tokens
 * are allowed to be transferred, and after all epochs have passed, the full
 * account balance is unlocked
 */


contract TimeLockedToken is VoteToken {
    using SafeMath for uint256;

    /* ============ Events ============ */


    /* ============ Modifiers ============ */

    modifier onlyTimeLockRegistry() {
        require(msg.sender == timeLockRegistry, "only TimeLockRegistry");
        _;
    }

    /* ============ State Variables ============ */


    // represents total distribution for locked balances
    mapping(address => uint256) distribution;

    // start of the lockup period
    // Monday, March 01, 2021 18:05:55 GMT + 1
    uint256 constant LOCK_START = 1614618355;

    // length of time to delay first epoch
    uint256 constant FIRST_EPOCH_DELAY = 365 days;

    // how long does an epoch last
    uint256 constant EPOCH_DURATION = 1 days;

    // number of epochs for Investors
    uint256 constant TOTAL_EPOCHS_INVESTORS = 365 days * 3;

     // number of epochs for Team Members
    uint256 constant TOTAL_EPOCHS_TEAM = 365 days * 4;

    // registry of locked addresses
    address public timeLockRegistry;

    // allow unlocked transfers to special account
    bool public returnsLocked;

    /* ============ Functions ============ */

    /* ============ Constructor ============ */

    constructor (string memory _name, string memory _symbol) VoteToken(_name, _symbol) {
    }

    /* ============ External Functions ============ */

    /* ===========  Token related Gov Functions ====== */

    /**
     * @dev Set TimeLockRegistry address
     * @param newTimeLockRegistry Address of TimeLockRegistry contract
     */
    function setTimeLockRegistry(address newTimeLockRegistry) external onlyOwner {
        require(newTimeLockRegistry != address(0), "cannot be zero address");
        require(newTimeLockRegistry != timeLockRegistry, "must be new TimeLockRegistry");
        timeLockRegistry = newTimeLockRegistry;
    }

    /**
     * @dev Permanently lock transfers to return address
     * Lock returns so there isn't always a way to send locked tokens
     */
    function lockReturns() external onlyOwner {
        returnsLocked = true;
    }

    /**
    * @dev Allows an account to transfer tokens to another account under the lockup schedule
    * locking them according to the distribution epoch periods
    * Emits a transfer event showing a transfer to the recipient
    * Only the registry can call this function
    * @param receiver Address to receive the tokens
    * @param amount Tokens to be transferred
    */
    function registerLockup(address receiver, uint256 amount) external onlyTimeLockRegistry {
        require(balanceOf(msg.sender) >= amount, "insufficient balance");

        // add amount to locked distribution
        distribution[receiver] = distribution[receiver].add(amount);

        // transfer to recipient
        _transfer(msg.sender, receiver, amount);
    }

     /**
     * @dev Get locked balance for an account
     * @param account Account to check
     * @return Amount locked
     */
    function lockedBalance(address account) public view returns (uint256) {
        // distribution * (epochsLeft / totalEpochs)
        return distribution[account].mul(epochsLeft()).div(TOTAL_EPOCHS_INVESTORS);
    }

    /**
     * @dev Get unlocked balance for an account
     * @param account Account to check
     * @return Amount that is unlocked and available eg. to transfer
     */
    function unlockedBalance(address account) public view returns (uint256) {
        require(balanceOf(account)>0,"TimeLockedToken:: _unlockedBalance: no tokens yet"); 
        // totalBalance - lockedBalance
        return balanceOf(account).sub(lockedBalance(account));
    }

    /*
     * @dev Get number of epochs passed
     * @return Value between 0 and 8 of lockup epochs already passed
     */
    function epochsPassed() public view returns (uint256) {
        // return 0 if timestamp is lower than start time
        if (block.timestamp < LOCK_START) {
            return 0;
        }

        // how long it has been since the beginning of lockup period
        uint256 timePassed = block.timestamp.sub(LOCK_START);

        // 1st epoch is FIRST_EPOCH_DELAY longer; we check to prevent subtraction underflow
        if (timePassed < FIRST_EPOCH_DELAY) {
            return 0;
        }

        // subtract the FIRST_EPOCH_DELAY, so that we can count all epochs as lasting EPOCH_DURATION
        uint256 totalEpochsPassed = timePassed.sub(FIRST_EPOCH_DELAY).div(EPOCH_DURATION);

        // epochs don't count over TOTAL_EPOCHS_INVESTORS
        if (totalEpochsPassed > TOTAL_EPOCHS_INVESTORS) {
            return TOTAL_EPOCHS_INVESTORS;
        }

        return totalEpochsPassed;
    }

    function epochsLeft() public view returns (uint256) {
        return TOTAL_EPOCHS_INVESTORS.sub(epochsPassed());
    }

    /**
     * @dev Get timestamp of next epoch
     * Will revert if all epochs have passed
     * @return Timestamp of when the next epoch starts
     */
    function nextEpoch() public view returns (uint256) {
        // get number of epochs passed
        uint256 passed = epochsPassed();

        // if all epochs passed, return
        if (passed == TOTAL_EPOCHS_INVESTORS) {
            // return INT_MAX
            return uint256(-1);
        }

        // if no epochs passed, return latest epoch + delay + standard duration
        if (passed == 0) {
            return latestEpoch().add(FIRST_EPOCH_DELAY).add(EPOCH_DURATION);
        }

        // otherwise return latest epoch + epoch duration
        return latestEpoch().add(EPOCH_DURATION);
    }

    /**
     * @dev Get timestamp of latest epoch
     * @return Timestamp of when the current epoch has started
     */
    function latestEpoch() public view returns (uint256) {
        // get number of epochs passed
        uint256 passed = epochsPassed();

        // if no epochs passed, return lock start time
        if (passed == 0) {
            return LOCK_START;
        }

        // accounts for first epoch being longer
        // lockStart + firstEpochDelay + (epochsPassed * epochDuration)
        return LOCK_START.add(FIRST_EPOCH_DELAY).add(passed.mul(EPOCH_DURATION));
    }

    /**
     * @dev Get timestamp of final epoch
     * @return Timestamp of when the last epoch ends and all funds are released
     */
    function finalEpoch() public pure returns (uint256) {
        // lockStart + firstEpochDelay + (epochDuration * totalEpochs)
        return LOCK_START.add(FIRST_EPOCH_DELAY).add(EPOCH_DURATION.mul(TOTAL_EPOCHS_INVESTORS));
    }

    /**
     * @dev Get timestamp of locking period start
     * @return Timestamp of locking period start
     */
    function lockStart() public pure returns (uint256) {
        return LOCK_START;
    }


    /* ============ Internal Only Function ============ */

    /**
     * @dev Transfer function which includes unlocked tokens
     * Locked tokens can always be transfered back to the returns address
     * Transferring to owner allows re-issuance of funds through registry
     *
     * @param _from The address to send tokens from
     * @param _to The address that will receive the tokens
     * @param _value The amount of tokens to be transferred
     */
    function _transfer(
        address _from,
        address _to,
        uint256 _value
    ) internal override {
        require(_from != address(0), "TimeLockedToken:: _transfer: cannot transfer from the zero address");
        require(_to != address(0), "TimeLockedToken:: _transfer: cannot transfer to the zero address");
        require(_to != address(this), "TimeLockedToken:: _transfer: do not transfer tokens to the token contract itself");

        require(balanceOf(_from) >= _value, "TimeLockedToken:: _transfer: insufficient balance");

        // check if enough unlocked balance to transfer
        require(unlockedBalance(_from) >= _value, "TimeLockedToken:: _transfer: attempting to transfer locked funds");
        super._transfer(_from, _to, _value);
    }
    

    /**
     * @notice Get the number of tokens held by the `account`
     * @param account The address of the account to get the balance of
     * @return The number of tokens held
     */

    function _balanceOf(address account) internal override view returns (uint256) {
        return unlockedBalance(account);
    }

}
