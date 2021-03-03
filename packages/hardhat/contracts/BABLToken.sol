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

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

// BABL Token with governance

contract BABLToken is Context, IERC20, Ownable {
    
    using SafeMath for uint256;
    using Address for address;

    /* ============ Events ============ */

    /// @notice An event thats emitted when the minter address is changed
    event MinterChanged(address minter, address newMinter);

    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    /// @notice The standard EIP-20 transfer event
    // event Transfer(address indexed from, address indexed to, uint256 value); TODO - CHECK DEFINITION IN IERC20

    /// @notice The standard EIP-20 approval event
    // event Approval(address indexed owner, address indexed spender, uint256 value); TODO - CHECK DEFINITION IN IERC20

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    /// @notice EIP-20 token name for this token
    string public constant name = "Babylon.Finance";

    /// @notice EIP-20 token symbol for this token
    string public constant symbol = "BABL";

    /// @notice EIP-20 token decimals for this token
    uint8 public constant decimals = 18;

    /// @notice Total number of tokens in circulation
    uint256 public _totalSupply = 1_000_000e18; // 1 million BABL
    
    /// @notice Maximum number of tokens in circulation
    uint public constant MAX_SUPPLY = 1_000_000e18; // 1 million BABL

    /// @notice Address which may mint new tokens
    address public minter;

    /// @notice The timestamp after which minting may occur
    uint public mintingAllowedAfter;

    /// @notice Minimum time between mints
    uint32 public constant minimumTimeBetweenMints = 1 days * 365;

    /// @notice Cap on the percentage of totalSupply that can be minted at each mint
    uint8 public constant mintCap = 2;

    /// @dev Allowance amounts on behalf of others
    mapping (address => mapping (address => uint96)) internal allowances;

    /// @dev Official record of token balances for each account
    mapping (address => uint96) internal balances;

    /// @notice A record of each accounts delegate
    mapping (address => address) public delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint96 votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice The EIP-712 typehash for the permit struct used by the contract
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @notice A record of states for signing / validating signatures
    mapping (address => uint) public nonces;

    
    /* ============ Functions ============ */

    /* ============ Constructor ============ */

    /**
     * @notice Construct a new BABL token
     * @param account The initial account to grant all the tokens
     * @param minter_ The account with minting ability
     * @param mintingAllowedAfter_ The timestamp after which minting may occur
     */
     
     
    constructor(address account, address minter_, uint mintingAllowedAfter_) { // TODO - CHECK
        require(mintingAllowedAfter_ >= block.timestamp, "BABL::constructor: minting can only begin after deployment");

        balances[account] = uint96(_totalSupply);
        emit Transfer(address(0), account, _totalSupply);
        minter = minter_;
        emit MinterChanged(address(0), minter);
        mintingAllowedAfter = mintingAllowedAfter_;
    }

    /* ============ External Functions ============ */

    // ===========  Token related Gov Functions ======

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to set the new minter
     *
     * @notice Change the minter address
     * @param _minter_ The address of the new minter
     */
    function setMinter(address _minter_) external onlyOwner {
        require(msg.sender == minter, "BABL::setMinter: only the minter can change the minter address");
        require(_minter_ != minter, "BABL::setMinter: you are already the minter"); // TODO ADDED TO AVOID GAS - CHECK
        emit MinterChanged(minter, _minter_);
        minter = _minter_;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to order the minter to mint new tokens
     *
     * @notice Mint new tokens
     * @param dst The address of the destination account
     * @param rawAmount The number of tokens to be minted
     */
    function mint(address dst, uint rawAmount) external onlyOwner {
        require(msg.sender == minter, "BABL::mint: only the minter can mint");
        require(SafeMath.add(_totalSupply, rawAmount)<= MAX_SUPPLY, "BABL::mint: max supply exceeded"); // TODO ADDED - CHECK
        require(rawAmount>0, "BABL::mint: mint should be higher than zero"); // TODO ADDED TO AVOID GAS - CHECK
        require(block.timestamp >= mintingAllowedAfter, "BABL::mint: minting not allowed yet");
        require(dst != address(0), "BABL::mint: cannot transfer to the zero address");

        // record the mint
        mintingAllowedAfter = SafeMath.add(block.timestamp, minimumTimeBetweenMints);

        // mint the amount
        uint96 amount = safe96(rawAmount, "BABL::mint: amount exceeds 96 bits");
        require(amount <= SafeMath.div(SafeMath.mul(_totalSupply, mintCap), 100), "BABL::mint: exceeded mint cap");
        _totalSupply = safe96(SafeMath.add(_totalSupply, amount), "BABL::mint: totalSupply exceeds 96 bits");

        // transfer the amount to the recipient
        balances[dst] = add96(balances[dst], amount, "BABL::mint: transfer amount overflows");
        emit Transfer(address(0), dst, amount);

        // move delegates
        _moveDelegates(address(0), delegates[dst], amount);
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
    function approve(address spender, uint rawAmount) external onlyOwner override returns (bool) { // TODO - CHECK OVERRIDE
        uint96 amount;
        if (rawAmount == uint(-1)) {
            amount = uint96(-1);
        } else {
            amount = safe96(rawAmount, "BABL::approve: amount exceeds 96 bits");
        }

        allowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Permission from owners to spenders to spend certain amount with deadline
     *
     * @notice Triggers an approval from owner to spends
     * @param owner The address to approve from
     * @param spender The address to be approved
     * @param rawAmount The number of tokens that are approved (2^256-1 means infinite)
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function permit(address owner, address spender, uint rawAmount, uint deadline, uint8 v, bytes32 r, bytes32 s) external onlyOwner {
        uint96 amount;
        if (rawAmount == uint(-1)) {
            amount = uint96(-1);
        } else {
            amount = safe96(rawAmount, "BABL::permit: amount exceeds 96 bits");
        }

        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, rawAmount, nonces[owner]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "BABL::permit: invalid signature");
        require(signatory == owner, "BABL::permit: unauthorized");
        require(block.timestamp <= deadline, "BABL::permit: signature expired");

        allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Transfer tokens
     *
     * @notice Transfer `amount` tokens from `msg.sender` to `dst`
     * @param dst The address of the destination account
     * @param rawAmount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address dst, uint rawAmount) external onlyOwner override returns (bool) { // TODO - CHECK OVERRIDE
        uint96 amount = safe96(rawAmount, "BABL::transfer: amount exceeds 96 bits");
        _transferTokens(msg.sender, dst, amount);
        return true;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Transfer tokens from source to destination
     *
     * @notice Transfer `amount` tokens from `src` to `dst`
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param rawAmount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(address src, address dst, uint rawAmount) external onlyOwner override returns (bool) { // TODO - CHECK OVERRIDE
        address spender = msg.sender;
        uint96 spenderAllowance = allowances[src][spender];
        uint96 amount = safe96(rawAmount, "BABL::approve: amount exceeds 96 bits");

        if (spender != src && spenderAllowance != uint96(-1)) {
            uint96 newAllowance = sub96(spenderAllowance, amount, "BABL::transferFrom: transfer amount exceeds spender allowance");
            allowances[src][spender] = newAllowance;

            emit Approval(src, spender, newAllowance);
        }

        _transferTokens(src, dst, amount);
        return true;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Delegating votes from msg.sender to delegatee
     *
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) public onlyOwner {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Delegating votes from signatory to 'delegatee'
     *
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(address delegatee, uint nonce, uint expiry, uint8 v, bytes32 r, bytes32 s) public onlyOwner {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "BABL::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "BABL::delegateBySig: invalid nonce");
        require(block.timestamp <= expiry, "BABL::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /* ============ External Getter Functions ============ */

    /**
     * Returns the remaining number of tokens that spender will be allowed to spend on behalf of owner through
     * @notice Get the number of tokens still available for spending by the spender on behalf of the `account`
     * @param account The address of the account that gave permission allowance to 'spender'
     * @param spender The address of the spender that has permission allowance from 'account'
     * @return The number of tokens available to spend on behalf
     */

    function allowance(address account, address spender) external view onlyOwner override returns (uint256) { // TODO - CHECK OVERRIDE
        return allowances[account][spender];
    }
    
    /**
     * @notice Get the number of totalSupply tokens
     * @return The number of totalSupply BABL tokens
     */
     
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }
    
    /**
     * @notice Get the number of tokens held by the `account`
     * @param account The address of the account to get the balance of
     * @return The number of tokens held
     */
    function balanceOf(address account) external view onlyOwner override returns (uint256) { // TODO - CHECK OVERRIDE
        return balances[account];
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint96) {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber) public view returns (uint96) {
        require(blockNumber < block.number, "BABL::getPriorVotes: not yet determined");

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

    /* ============ Internal Only Function ============ */
    
    /**
     * PRIVILEGED FACTORY FUNCTION. Disable the burning of any BABL tokens
     *
     * @notice Override  burn function to avoid BABL token burning
     * @param account The address of the account holding the funds
     * @param amount The amount of tokens requested to burn
     * 
     */ 

    function _burn(address account, uint256 amount) internal virtual { // TODO - CHECK OVERRIDE TO AVOID BURNING
        revert("BABL::burn: cannot burn tokens");
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Make a delegation
     *
     * @notice Make a delegation
     * @param delegator The address of the account delegating into delegatee
     * @param delegatee The address to delegate into
     * 
     */

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint96 delegatorBalance = balances[delegator];
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Make a transfer of tokens from src to dst
     *
     * @notice Make a Token Transfer
     * @param src The address of the account originating the transfer
     * @param dst The receiving address
     * @param amount The amount sent
     * 
     */

    function _transferTokens(address src, address dst, uint96 amount) internal {
        require(src != address(0), "BABL::_transferTokens: cannot transfer from the zero address");
        require(dst != address(0), "BABL::_transferTokens: cannot transfer to the zero address");

        balances[src] = sub96(balances[src], amount, "BABL::_transferTokens: transfer amount exceeds balance");
        balances[dst] = add96(balances[dst], amount, "BABL::_transferTokens: transfer amount overflows");
        emit Transfer(src, dst, amount);

        _moveDelegates(delegates[src], delegates[dst], amount);
    }

    function _moveDelegates(address srcRep, address dstRep, uint96 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint96 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint96 srcRepNew = sub96(srcRepOld, amount, "BABL::_moveVotes: vote amount underflows");
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint96 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint96 dstRepNew = add96(dstRepOld, amount, "BABL::_moveVotes: vote amount overflows");
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(address delegatee, uint32 nCheckpoints, uint96 oldVotes, uint96 newVotes) internal {
      uint32 blockNumber = safe32(block.number, "BABL::_writeCheckpoint: block number exceeds 32 bits");

      if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
          checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
      } else {
          checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
          numCheckpoints[delegatee] = nCheckpoints + 1;
      }

      emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function safe96(uint n, string memory errorMessage) internal pure returns (uint96) {
        require(n < 2**96, errorMessage);
        return uint96(n);
    }

    function add96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
        uint96 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
        require(b <= a, errorMessage);
        return a - b;
    }

    function getChainId() internal pure returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }
}