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

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IVoteToken } from "./interfaces/IVoteToken.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";  


/**
 * @title VoteToken
 * @notice Custom token which tracks voting power for governance
 * @dev This is an abstraction of a fork of the Compound governance contract
 * VoteToken is used by BABL to allow tracking voting power
 * Checkpoints are created every time state is changed which record voting power
 * Inherits standard ERC20 behavior
 */

contract VoteToken is Context, ERC20, Ownable, IVoteToken, ReentrancyGuard {
    using SafeMath for uint256;
    using Address for address;


    /* ============ Events ============ */

    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);


    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    string public _name;
    string public _symbol;
    
    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice The EIP-712 typehash for the permit struct used by the contract // TODO - CHECK
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @dev override of ERC20 _allowances
    mapping (address => mapping (address => uint256)) public _allowances;
    
    /// @dev A record of votes checkpoints for each account, by index
    mapping(address => address) public delegates; 
    
    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint96 votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    /// @notice A record of states for signing / validating signatures
    mapping (address => uint) public nonces;

    /* ============ Functions ============ */
    
    /* ============ Constructor ============ */

    constructor () ERC20 (_name, _symbol) {
    }
    
    /* ============ External Functions ============ */

    /* ===========  Token related Gov Functions ====== */

    /**
    * PRIVILEGED GOVERNANCE FUNCTION. Delegating votes from msg.sender to delegatee
    *
    * @notice Delegate votes from `msg.sender` to `delegatee`
    * @param delegatee The address to delegate votes to
    */

    function delegate(address delegatee) public override {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Delegate votes using signature to 'delegatee'
     *
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override { // TODO - CHECK IF SIGNATURE CAN BE != MSG_SENDER TO AVOID IT
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "BABLToken::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "BABLToken::delegateBySig: invalid nonce");
        require(block.timestamp <= expiry, "BABLToken::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @dev Get current voting power for an account
     * @param account Account to get voting power for
     * @return Voting power for an account
     */
    function getCurrentVotes(address account) public virtual override view returns (uint96) {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @dev Get voting power at a specific block for an account
     * @param account Account to get voting power for
     * @param blockNumber Block to get voting power at
     * @return Voting power for an account at specific block
     */
    function getPriorVotes(address account, uint256 blockNumber) public virtual override view returns (uint96) {
        require(blockNumber < block.number, "BABLToken::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
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
        uint96 amount;
        if (rawAmount == uint(-1)) {
            amount = uint96(-1);
        } else {
            amount = safe96(rawAmount, "BABL::approve: amount exceeds 96 bits");
        }

        _allowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /* ============ Internal Only Function ============ */

    /**
    * PRIVILEGED GOVERNANCE FUNCTION. Make a delegation
    *
    * @dev Internal function to delegate voting power to an account
    * @param delegator The address of the account delegating votes from 
    * @param delegatee The address to delegate votes to
    */

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint96 delegatorBalance = safe96(_balanceOf(delegator), "BABLToken: uint96 overflow");
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _balanceOf(address account) internal view virtual returns (uint256) {
        return balanceOf(account);
    }


    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Make a transfer of tokens from _from to _to
     *
     * @notice Make a Token Transfer
     * @param _from The address of the account originating the transfer
     * @param _to The receiving address
     * @param _value The amount sent
     * @return Whether or not the transfer succeeded
     */
    function _transfer(
        address _from,
        address _to,
        uint96 _value
    ) internal virtual nonReentrant returns (bool) { // TODO - CHECK WHY OVERRIDE WAS NOT WORKING PROPERLY
    
        address spender = msg.sender;
        uint96 spenderAllowance = safe96(_allowances[_from][spender], "BABL::_transfer: allowances exceeds 96 bits");
        uint96 amount = safe96(_value, "BABL::_transfer: amount exceeds 96 bits");
        require(_from != address(0), "BABL::_transfer: cannot transfer from the zero address");
        require(_to != address(0), "BABL::_transfer: cannot transfer to the zero address");
        require(_to != address(this), "BABL::_transfer: do not transfer tokens to the token contract itself!!");
        
        // TODO - CHECK ALLOWANCES

        if (spender != _from && spenderAllowance != uint96(-1)) {
            uint96 newAllowance = sub96(spenderAllowance, amount, "BABL::_transfer: transfer amount exceeds spender allowance");
            _allowances[_from][spender] = newAllowance;

            emit Approval(_from, spender, newAllowance);
        }
        
        super._transfer(_from, _to, amount);
        _moveDelegates(delegates[_from], delegates[_to], safe96(amount, "BABLToken: uint96 overflow"));
        return true;
    }
    
    function _mint(address account, uint256 amount) internal virtual override nonReentrant {
        super._mint(account, amount);
        _moveDelegates(address(0), delegates[account], safe96(amount, "BABLToken: uint96 overflow"));
    }


    function _burn(address account, uint256 amount) internal virtual override {
        super._burn(account, amount);
        _moveDelegates(delegates[account], address(0), safe96(amount, "BABLToken: uint96 overflow"));
    }


    /**
     * @dev internal function to move delegates between accounts
     */
    function _moveDelegates(
        address srcRep,
        address dstRep,
        uint96 amount
    ) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint96 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint96 srcRepNew = sub96(srcRepOld, amount, "BABLToken::_moveVotes: vote amount underflows");
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint96 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint96 dstRepNew = add96(dstRepOld, amount, "BABLToken::_moveVotes: vote amount overflows");
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    /** 
     * @dev internal function to write a checkpoint for voting power
     */
    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint96 oldVotes,
        uint96 newVotes
    ) internal {
        uint32 blockNumber = safe32(block.number, "BABLToken::_writeCheckpoint: block number exceeds 32 bits");

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    /**
     * @dev internal function to convert from uint256 to uint32
     */
    function safe32(uint256 n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    /**
     * @dev internal function to convert from uint256 to uint96
     */
    function safe96(uint256 n, string memory errorMessage) internal pure returns (uint96) {
        require(n < 2**96, errorMessage);
        return uint96(n);
    }

    /**
     * @dev internal safe math function to add two uint96 numbers
     */
    function add96(
        uint96 a,
        uint96 b,
        string memory errorMessage
    ) internal pure returns (uint96) {
        uint96 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    /**
     * @dev internal safe math function to subtract two uint96 numbers
     */
    function sub96(
        uint96 a,
        uint96 b,
        string memory errorMessage
    ) internal pure returns (uint96) {
        require(b <= a, errorMessage);
        return a - b;
    }

    /** 
     * @dev internal function to get chain ID
     */
    function getChainId() internal pure returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}