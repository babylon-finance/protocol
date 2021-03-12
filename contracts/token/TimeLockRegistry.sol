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

import { TimeLockedToken } from "./TimeLockedToken.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title TimeLockRegistry
 * @notice Register Lockups for TimeLocked ERC20 Token BABL
 * @author Babylon Finance after modifying a version of TimeLockedToken provided by Harold Hyatt 
 * @dev This contract allows owner to register distributions for a TimeLockedToken
 *
 * To register a distribution, register method should be called by the owner.
 * claim() should then be called by account registered to recieve tokens under lockup period
 * If case of a mistake, owner can cancel registration
 *
 * Note this contract must be setup in TimeLockedToken's setTimeLockRegistry() function
 */

contract TimeLockRegistry is Ownable {
    using SafeMath for uint256;
    using Address for address;
    
    /* ============ Events ============ */

    event Register(address receiver, uint256 distribution);
    event Cancel(address receiver, uint256 distribution);
    event Claim(address account, uint256 distribution);

    /* ============ Modifiers ============ */
    
    modifier onlyBABLToken() {
        require(msg.sender == address(token), "only BABL Token");
        _;
    }
    
    /* ============ State Variables ============ */


    // time locked token
    TimeLockedToken public token;

    /// @notice The profile of each token owner under vesting conditions and its special conditions 
    /**
    * @param team Indicates whether or not is a Team member (true = team member / advisor, false = private investor)
    * @param vestingBegin When the vesting begins for such token owner
    * @param vestingEnd When the vesting ends for such token owner
    */
    struct TokenVested {
        bool team;
        bool cliff;
        uint256 vestingBegin;
        uint256 vestingEnd;
        uint256 lastClaim;
    }

    /// @notice A record of token owners under vesting conditions for each account, by index
    mapping (address => TokenVested) public tokenVested;
    
    // mapping from token owners under vesting conditions to BABL due amount (e.g. SAFT addresses, team members, advisors) 
    mapping(address => uint256) public registeredDistributions;
    
    // vesting Cliff just for Team Members
    uint256 private vestingCliff = 365 days;
    
    // vesting for Team Members
    uint256 private teamVesting = 365 days * 4;
    
    // vesting for Investors and Advisors
    uint256 private investorVesting = 365 days * 3;

    /* ============ Functions ============ */

    /* ============ Constructor ============ */

    /**
    * @notice Construct a new Time Lock Registry and gives ownership to sender
    * @param _token TimeLockedToken contract to use in this registry
     */
    constructor(TimeLockedToken _token) { // TODO - CHECK
        token = _token;
        
    }

    /* ============ External Functions ============ */

    /* ===========  Token related Gov Functions ====== */

    /**
     * @dev Register new SAFT account
     * @param receiver Address belonging to SAFT purchaser
     * @param distribution Tokens amount that receiver is due to get
     */
    function register(address receiver, uint256 distribution, bool investorType, uint vestingStartingDate) external onlyOwner returns (bool) {
        require(receiver != address(0), "Zero address");
        require(distribution != 0, "Distribution = 0");
        require(registeredDistributions[receiver] == 0, "Distribution for this address is already registered");

        // register distribution in mapping
        registeredDistributions[receiver] = distribution;
        
        // register distribution in token vested
        TokenVested storage newTokenVested = tokenVested[receiver];
        newTokenVested.team = investorType;
        newTokenVested.vestingBegin = vestingStartingDate;

        
        if (newTokenVested.team == true){
            newTokenVested.vestingEnd = vestingStartingDate.add(teamVesting);
            // Team members & advisors have Cliff of 1 year
            newTokenVested.cliff = true;
        }
        else {
            newTokenVested.vestingEnd = vestingStartingDate.add(investorVesting);
            // Investors has not Cliff
            newTokenVested.cliff = false;
        }
        newTokenVested.lastClaim = vestingStartingDate;
        
        tokenVested[receiver] = newTokenVested;

        // transfer tokens from owner
        require(token.transferFrom(msg.sender, address(this), distribution), "Transfer failed");

        // emit register event
        emit Register(receiver, distribution);
        
        return true;
    }

    /**
     * @dev Cancel distribution registration
     * @param receiver Address that should have it's distribution removed
     */
    function cancelRegistration(address receiver) external onlyOwner {
        require(registeredDistributions[receiver] != 0, "Not registered");

        // get amount from distributions
        uint256 amount = registeredDistributions[receiver];

        // set distribution mapping to 0
        delete registeredDistributions[receiver];
        
         // set tokenVested mapping to 0
        delete tokenVested[receiver];

        // transfer tokens back to owner
        require(token.transfer(msg.sender, amount), "Transfer failed");

        // emit cancel event
        emit Cancel(receiver, amount);
    }
    
    function cancelDeliveredTokens(address receiver) external onlyOwner {
       
        uint256 loosingAmount = token.cancelTokens(receiver);

        // emit cancel event
        emit Cancel(receiver, loosingAmount);
    }

    /// @dev Claim tokens due amount
    function claim(address _receiver) external onlyBABLToken returns (uint256){
        require(registeredDistributions[_receiver] != 0, "Not registered");

        // get amount from distributions
        uint256 amount = registeredDistributions[_receiver];
        tokenVested[_receiver].lastClaim = block.timestamp;

        // set distribution mapping to 0
        delete registeredDistributions[_receiver];

        // register lockup in TimeLockedToken
        
        // this will transfer funds from this contract and lock them for sender
        token.registerLockup(_receiver, amount, tokenVested[_receiver].team, tokenVested[_receiver].cliff, tokenVested[_receiver].vestingBegin, tokenVested[_receiver].vestingEnd, tokenVested[_receiver].lastClaim);
        
        // set tokenVested mapping to 0
        delete tokenVested[_receiver];

        // emit claim event
        emit Claim(_receiver, amount);
    
        
        return amount;
    }
}