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

//import "hardhat/console.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { VoteToken } from "../governance/VoteToken.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TimeLockedToken
 * @notice Time Locked ERC20 Token
 * @author Babylon Finance after modifying a version of TimeLockedToken provided by Harold Hyatt
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
    event newTimeLockRegistration(address account);
    
    /// @notice An event that emitted when a cancellation of Lock tokens is registered 
    event Cancel(address account, uint256 amount);


    /* ============ Modifiers ============ */

    modifier onlyTimeLockRegistry() {
        require(msg.sender == timeLockRegistry, "only TimeLockRegistry");
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
    
    // registry of Time Lock Registry
    address public timeLockRegistry;
    


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
    function setTimeLockRegistry(address newTimeLockRegistry) external onlyOwner returns(bool){
        require(newTimeLockRegistry != address(0), "cannot be zero address");
        require(newTimeLockRegistry != address(this), "cannot be this contract");
        require(newTimeLockRegistry != timeLockRegistry, "must be new TimeLockRegistry");
        timeLockRegistry = newTimeLockRegistry;
        
        emit newTimeLockRegistration(newTimeLockRegistry);
        
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
        require(_receiver != timeLockRegistry, "cannot be the TimeLockRegistry contract itself");
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
     * @param lockedAccount that should have it's still locked distribution removed due to non-completion of its cliff or vesting period
     */
    function cancelTokens(address lockedAccount) public onlyOwner {
        require(distribution[lockedAccount] != 0, "Not registered");

        // get amount from distributions
        uint256 loosingAmount = lockedBalance(lockedAccount);
        
        // set distribution mapping to 0
        delete distribution[lockedAccount];
        
         // set tokenVested mapping to 0
        delete vestedToken[lockedAccount];

        // transfer tokens back to owner
        require(transferFrom(lockedAccount, msg.sender, loosingAmount), "Transfer failed");

        // emit cancel event
        emit Cancel(lockedAccount, loosingAmount);
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
