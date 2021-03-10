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
 * @author Babylon Finance modified a version of TimeLockedToken provided by Harold Hyatt 
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
    
    /* ============ State Variables ============ */


    // time locked token
    TimeLockedToken public token;

    // mapping from SAFT address to BABL due amount
    mapping(address => uint256) public registeredDistributions;

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
    function register(address receiver, uint256 distribution) external onlyOwner {
        require(receiver != address(0), "Zero address");
        require(distribution != 0, "Distribution = 0");
        require(registeredDistributions[receiver] == 0, "Distribution for this address is already registered");

        // register distribution in mapping
        registeredDistributions[receiver] = distribution;

        // transfer tokens from owner
        require(token.transferFrom(msg.sender, address(this), distribution), "Transfer failed");

        // emit register event
        emit Register(receiver, distribution);
    }

    /**
     * @dev Cancel distribution registration
     * @param receiver Address that should have it's distribution removed
     */
    function cancel(address receiver) external onlyOwner {
        require(registeredDistributions[receiver] != 0, "Not registered");

        // get amount from distributions
        uint256 amount = registeredDistributions[receiver];

        // set distribution mapping to 0
        delete registeredDistributions[receiver];

        // transfer tokens back to owner
        require(token.transfer(msg.sender, amount), "Transfer failed");

        // emit cancel event
        emit Cancel(receiver, amount);
    }

    /// @dev Claim tokens due amount
    function claim() external {
        require(registeredDistributions[msg.sender] != 0, "Not registered");

        // get amount from distributions
        uint256 amount = registeredDistributions[msg.sender];

        // set distribution mapping to 0
        delete registeredDistributions[msg.sender];

        // register lockup in TimeLockedToken
        // this will transfer funds from this contract and lock them for sender
        token.registerLockup(msg.sender, amount);

        // emit claim event
        emit Claim(msg.sender, amount);
    }
}