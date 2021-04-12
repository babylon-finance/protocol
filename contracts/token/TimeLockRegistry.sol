/*
    Copyright 2021 Babylon Finance.
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

import 'hardhat/console.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {TimeLockedToken} from './TimeLockedToken.sol';

/**
 * @title TimeLockRegistry
 * @notice Register Lockups for TimeLocked ERC20 Token BABL (e.g. vesting)
 * @author Babylon Finance
 * @dev This contract allows owner to register distributions for a TimeLockedToken
 *
 * To register a distribution, register method should be called by the owner.
 * claim() should be called only by the BABL Token smartcontract (modifier onlyBABLToken)
 *  when any account registered to receive tokens make its own claim
 * If case of a mistake, owner can cancel registration before the claim is done by the account
 *
 * Note this contract address must be setup in the TimeLockedToken's contract pointing
 * to interact with (e.g. setTimeLockRegistry() function)
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
        require(msg.sender == address(token), 'only BABL Token');
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
     * @param lastClaim When the last claim was done
     */
    struct TokenVested {
        bool team;
        bool cliff;
        uint256 vestingBegin;
        uint256 vestingEnd;
        uint256 lastClaim;
    }

    /// @notice A record of token owners under vesting conditions for each account, by index
    mapping(address => TokenVested) public tokenVested;

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
    constructor(TimeLockedToken _token) {
        token = _token;
    }

    /* ============ External Functions ============ */

    /* ===========  Token related Gov Functions ====== */

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Register new account under vesting conditions (Team, Advisors, Investors e.g. SAFT purchaser)
     *
     * @notice Register new account under vesting conditions (Team, Advisors, Investors e.g. SAFT purchaser)
     * @param receiver Address belonging vesting conditions
     * @param distribution Tokens amount that receiver is due to get
     * @return Whether or not the registration succeeded
     */
    function register(
        address receiver,
        uint256 distribution,
        bool investorType,
        uint256 vestingStartingDate
    ) external onlyOwner returns (bool) {
        require(receiver != address(0), 'TimeLockRegistry::register: cannot register the zero address');
        require(
            receiver != address(this),
            'TimeLockRegistry::register: Time Lock Registry contract cannot be an investor'
        );
        require(distribution != 0, 'TimeLockRegistry::register: Distribution = 0');
        require(
            registeredDistributions[receiver] == 0,
            'TimeLockRegistry::register:Distribution for this address is already registered'
        );

        // register distribution
        registeredDistributions[receiver] = distribution;

        // register token vested conditions
        TokenVested storage newTokenVested = tokenVested[receiver];
        newTokenVested.team = investorType;
        newTokenVested.vestingBegin = vestingStartingDate;

        if (newTokenVested.team == true) {
            newTokenVested.vestingEnd = vestingStartingDate.add(teamVesting);
        } else {
            newTokenVested.vestingEnd = vestingStartingDate.add(investorVesting);
        }
        newTokenVested.lastClaim = vestingStartingDate;

        tokenVested[receiver] = newTokenVested;
        // TODO CHECK IF ALLOWANCE AS OF TODAY IS THE FINAL MODEL
        // IN CASE OF A DIRECT MINT TO TIME LOCK REGISTRY ADDRESS THE TOKEN TRANSFER MIGHT BE UPDATED
        // transfer tokens from owner who might have enough allowance of tokens by BABL Token owner
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), distribution);

        // emit register event
        emit Register(receiver, distribution);

        return true;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Cancel distribution registration in case of mistake and before a claim is done
     *
     * @notice Cancel distribution registration
     * @dev A claim has not to be done earlier
     * @param receiver Address that should have it's distribution removed
     * @return Whether or not it succeeded
     */
    function cancelRegistration(address receiver) external onlyOwner returns (bool) {
        require(registeredDistributions[receiver] != 0, 'Not registered');

        // get amount from distributions
        uint256 amount = registeredDistributions[receiver];

        // set distribution mapping to 0
        delete registeredDistributions[receiver];

        // set tokenVested mapping to 0
        delete tokenVested[receiver];

        // TODO CHECK THE PROCESS ADDRESS(THIS) VS. OWNER
        // transfer tokens back to owner
        SafeERC20.safeTransfer(token, msg.sender, amount);

        // emit cancel event
        emit Cancel(receiver, amount);

        return true;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Cancel distribution registration in case of mistake and before a claim is done
     *
     * @notice Cancel already delivered tokens. It might only apply when non-completion of vesting period of Team members or Advisors
     * @dev An automatic override allowance is granted during the claim process
     * @param account Address that should have it's distribution removed
     * @return Whether or not it succeeded
     */
    function cancelDeliveredTokens(address account) public onlyOwner returns (bool) {
        uint256 loosingAmount = token.cancelVestedTokens(account);

        // emit cancel event
        emit Cancel(account, loosingAmount);
        return true;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Recover tokens in Time Lock Registry smartcontract address by the owner
     *
     * @notice Send tokens from smartcontract address to the owner.
     * It might only apply after a cancellation of vested tokens
     * @param amount Amount to be recovered by the owner of the Time Lock Registry smartcontract from its balance
     * @return Whether or not it succeeded
     */
    function transferToOwner(uint256 amount) public onlyOwner returns (bool) {
        SafeERC20.safeTransfer(token, msg.sender, amount);
        return true;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Claim locked tokens by the registered account
     *
     * @notice Claim tokens due amount.
     * @dev Claim is done by the user in the TimeLocked contract and the contract is the only allowed to call
     * this function on behalf of the user to make the claim
     * @return The amount of tokens registered and delivered after the claim
     */
    function claim(address _receiver) external onlyBABLToken returns (uint256) {
        require(registeredDistributions[_receiver] != 0, 'Not registered');

        // get amount from distributions
        uint256 amount = registeredDistributions[_receiver];
        tokenVested[_receiver].lastClaim = block.timestamp;

        // set distribution mapping to 0
        delete registeredDistributions[_receiver];

        // register lockup in TimeLockedToken

        // this will transfer funds from this contract and lock them for sender
        token.registerLockup(
            _receiver,
            amount,
            tokenVested[_receiver].team,
            tokenVested[_receiver].vestingBegin,
            tokenVested[_receiver].vestingEnd,
            tokenVested[_receiver].lastClaim
        );

        // set tokenVested mapping to 0
        delete tokenVested[_receiver];

        // emit claim event
        emit Claim(_receiver, amount);

        return amount;
    }

    /* ============ Getter Functions ============ */

    function checkVesting(address address_)
        public
        view
        returns (
            bool team,
            uint256 start,
            uint256 end,
            uint256 last
        )
    {
        return (
            tokenVested[address_].team,
            tokenVested[address_].vestingBegin,
            tokenVested[address_].vestingEnd,
            tokenVested[address_].lastClaim
        );
    }

    function checkRegisteredDistribution(address address_) public view returns (uint256 amount) {
        return registeredDistributions[address_];
    }
}
