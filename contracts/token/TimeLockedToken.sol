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
import { TimeLockRegistry } from "./TimeLockRegistry.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { VoteToken } from "../governance/VoteToken.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";


/**
 * @title TimeLockedToken
 * @notice Time Locked ERC20 Token
 * @author Babylon Finance
 * @dev Contract which gives the ability to time-lock tokens
 *
 * By overriding the balanceOf() and transfer()
 * functions in ERC20, an account can show its full, post-distribution
 * balance but only transfer or spend up to an allowed amount
 *
 * A portion of previously non-spendable tokens are allowed to be transferred
 * along the time depending on each vesting conditions, and after all epochs have passed, the full
 * account balance is unlocked. In case on non-completion vesting period, only the owner can cancel 
 * the delivery of the pending tokens.
 */


abstract contract TimeLockedToken is VoteToken {
    using SafeMath for uint256;

    /* ============ Events ============ */

    /// @notice An event that emitted when a new lockout ocurr
    event newLockout(address account, uint256 tokenslocked, bool isTeamOrAdvisor, uint256 startingVesting, uint256 endingVesting);
    
    /// @notice An event that emitted when a new Time Lock is registered
    event newTimeLockRegistration(address previousAddress, address newAddress);
    
    /// @notice An event that emitted when a cancellation of Lock tokens is registered 
    event Cancel(address account, uint256 amount);
    
    /// @notice An event that emitted when a claim of tokens are registered
    event Claim(address _receiver, uint256 amount);


    /* ============ Modifiers ============ */

    modifier onlyTimeLockRegistry() {
        require(msg.sender == address(timeLockRegistry), "only TimeLockRegistry");
        _;
    }

    /* ============ State Variables ============ */


    // represents total distribution for locked balances
    mapping(address => uint256) distribution;

    /// @notice The profile of each token owner under vesting conditions and its special conditions 
    /**
    * @param team Indicates whether or not is a Team member or Advisor (true = team member/advisor, false = private investor)
    * @param vestingBegin When the vesting begins for such token owner
    * @param vestingEnd When the vesting ends for such token owner
    */
    struct VestedToken {
        bool teamOrAdvisor;
        bool cliff;
        uint256 vestingBegin;
        uint256 vestingEnd;
        uint256 lastClaim;
    }

    /// @notice A record of token owners under vesting conditions for each account, by index
    mapping (address => VestedToken) public vestedToken;
    
    // vesting Cliff for Team Members and Advisors
    uint256 private vestingCliff = 365 days;
    
    // vesting for Team Members
    uint256 private teamVesting = 365 days * 4;
    
    // vesting for Investors and Advisors
    uint256 private investorVesting = 365 days * 3;
    
    // address of Time Lock Registry
    TimeLockRegistry public timeLockRegistry;
    


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
    function setTimeLockRegistry(TimeLockRegistry newTimeLockRegistry) external onlyOwner returns(bool){
        //console.log(" %s is the new timelockRegistry", newTimeLockRegistry);
        //console.log(" %s is the old timelockRegistry", timeLockRegistry);

        require(address(newTimeLockRegistry) != address(0), "cannot be zero address");
        require(address(newTimeLockRegistry) != address(this), "cannot be this contract");
        require(address(newTimeLockRegistry) != address(timeLockRegistry), "must be new TimeLockRegistry");        
        emit newTimeLockRegistration(address(timeLockRegistry), address(newTimeLockRegistry));

        timeLockRegistry = newTimeLockRegistry;

        
        return true;
    }


    /**
    * @dev Allows an account to transfer tokens to another account under the lockup schedule
    * locking them according to the distribution epoch periods
    * Emits a transfer event showing a transfer to the recipient
    * Only the registry can call this function
    * @param _receiver Address to receive the tokens
    * @param _amount Tokens to be transferred
    * @param _profile True if is a Team Member or Advisor
    * @param _cliff True if is a Team Member or Advisor under cliff clause
    * @param _vestingBegin Unix Time when the vesting for that particular address
    * @param _vestingEnd Unix Time when the vesting for that particular address
    * @param _lastClaim Unix Time when the claim was done from that particular address
    *
    */
    function registerLockup(address _receiver, uint256 _amount, bool _profile, bool _cliff, uint256 _vestingBegin, uint256 _vestingEnd, uint256 _lastClaim) external onlyTimeLockRegistry returns (bool) {
        require(balanceOf(msg.sender) >= _amount, "insufficient balance");
        require(_receiver != address(0), "cannot be zero address");
        require(_receiver != address(this), "cannot be this contract");
        require(_receiver != address(timeLockRegistry), "cannot be the TimeLockRegistry contract itself");
        require(_receiver != msg.sender, "the owner cannot lockup itself");
        
        // update amount of locked distribution
        distribution[_receiver] = distribution[_receiver].add(_amount);
        
        VestedToken storage newVestedToken = vestedToken[_receiver];
        
        newVestedToken.teamOrAdvisor = _profile;
        newVestedToken.cliff = _cliff;
        newVestedToken.vestingBegin = _vestingBegin;
        newVestedToken.vestingEnd = _vestingEnd;
        newVestedToken.lastClaim = _lastClaim;
        
        vestedToken[_receiver]=newVestedToken;
        

        // transfer to recipient
        _transfer(msg.sender, _receiver, _amount);
        emit newLockout(_receiver, _amount, _profile, _vestingBegin, _vestingEnd);
        
        return true;
    }
    
    /**
     * @dev Cancel distribution registration
     * @param lockedAccount that should have its still locked distribution removed due to non-completion of its cliff or vesting period
     */
    function cancelTokens(address lockedAccount) public onlyTimeLockRegistry returns (uint256) {
        require(distribution[lockedAccount] != 0, "Not registered");

        // get an update on locked amount from distributions at this precise moment
        uint256 loosingAmount = lockedBalance(lockedAccount);
        
        require(loosingAmount > 0, "There are no more locked tokens");

        // set distribution mapping to 0
        delete distribution[lockedAccount];
        
         // set tokenVested mapping to 0
        delete vestedToken[lockedAccount];

        // transfer only locked tokens back to TimeLockRegistry
        require(transferFrom(lockedAccount, address(timeLockRegistry), loosingAmount), "Transfer failed");

        // emit cancel event
        emit Cancel(lockedAccount, loosingAmount);
        
        return loosingAmount;
    }
    
    function claimMyTokens() public {
        
        // claim our tokens from timeLockRegistry
        uint256 amount = timeLockRegistry.claim(msg.sender);
        
        require(amount > 0, "No tokens to claim");
        
        // After a proper claim, locked tokens are under restricted vesting giving the owner the possibility to only retire locked tokens if non-compliance vesting conditions take places
        approve(address(timeLockRegistry), amount); // TODO-CHECK RESTRICTIONS TO DECREASE ALLOWANCE TO OWNER BY MSG.SENDER

        // emit claim event
        emit Claim(msg.sender, amount);
    }
    
    /**
     * @dev Get unlocked balance for an account
     * @param account Account to check
     * @return Amount that is unlocked and available eg. to transfer
     */
    function unlockedBalance(address account) public returns (uint256) {
        // totalBalance - lockedBalance
        return balanceOf(account).sub(lockedBalance(account));
    }
    
    
    /**
    * @dev Get locked balance for an account
    * @param account Account to check
    * @return Amount locked
    */
    function lockedBalance(address account) public returns (uint256) {
        // distribution of locked tokens
        // get amount from distributions
        
        uint256 amount = distribution[account];
        uint256 lockedAmount = amount;
        
        if (vestedToken[account].cliff == true && (block.timestamp < vestedToken[account].vestingBegin.add(vestingCliff))) {
            return lockedAmount;
        } 

        if (block.timestamp >= vestedToken[account].vestingEnd) {
            lockedAmount = 0;
            if (msg.sender == account) {// set distribution mapping to 0
            delete distribution[account];
            }
        } else {
            lockedAmount = amount.mul(vestedToken[account].vestingEnd - block.timestamp).div(vestedToken[account].vestingEnd - vestedToken[account].vestingBegin);
            vestedToken[account].lastClaim = block.timestamp;
        }
        return lockedAmount;
    }

    function getTimeLockRegistry() public view returns (address) {
        return address(timeLockRegistry);
    }
    
    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Approve the allowances
     *
     * @notice Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * @param spender The address of the account which may transfer tokens
     * @param rawAmount The number of tokens that are approved (2^256-1 means infinite)
     * @return Whether or not the approval succeeded
     */
    function approve(address spender, uint rawAmount) public virtual override nonReentrant returns (bool) { // TODO - CHECK OVERRIDE
        require(spender != address(0), "TimeLockedToken::approve: spender cannot be zero address");
        require(spender != msg.sender, "Spender cannot be the msg.sender");
        
        uint96 amount;
        if (rawAmount == uint(-1)) {
            amount = uint96(-1);
        } else {
            amount = safe96(rawAmount, "TimeLockedToken::approve: amount exceeds 96 bits");
        }
        
        // There is no option to decreaseAllowance to timeLockRegistry in case of vested tokens
        if ((spender == address(timeLockRegistry)) && (amount < allowance(msg.sender, address(timeLockRegistry)))) {
            amount = safe96(allowance(msg.sender, address(timeLockRegistry)), "TimeLockedToken::approve: amount exceeds 96 bits");
        }
        _approve(msg.sender, spender, amount);
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    /**
    * @dev Atomically increases the allowance granted to `spender` by the caller.
    *
    * This is an override with respect to the fulfillment of vesting conditions along the way
    * However an user can increase allowance many times, it will never be able to transfer locked tokens during vesting period
    */
    function increaseAllowance(address spender, uint256 addedValue) public override returns (bool) {
        require(unlockedBalance(msg.sender) >= addedValue, "Not enough unlocked tokens");
        require(spender != address(0), "Spender cannot be zero address");
        require(spender != msg.sender, "Spender cannot be the msg.sender");
        approve(spender, allowance(msg.sender, spender).add(addedValue));
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
    * This is an override with respect to the fulfillment of vesting conditions along the way
    * An user cannot decrease the allowance to the Time Lock Registry who is in charge of vesting conditions
    */
    function decreaseAllowance(address spender, uint256 subtractedValue) public override returns (bool) {
        require(spender != address(0), "TimeLockedToken::decreaseAllowance:Spender cannot be zero address");
        require(allowance(msg.sender,spender) >= subtractedValue, "TimeLockedToken::decreaseAllowance:Underflow condition");
        require(spender != msg.sender, "TimeLockedToken::decreaseAllowance:Spender cannot be the msg.sender");

        
        // There is no option to decreaseAllowance to timeLockRegistry in case of vested tokens
        require(address(spender) != address(timeLockRegistry), "TimeLockedToken::decreaseAllowance: cannot decrease allowance to timeLockRegistry");
        
        approve(spender, allowance(msg.sender, spender).sub(subtractedValue));
        return true;
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

    
}