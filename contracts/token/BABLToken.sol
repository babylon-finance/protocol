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
import { TimeLockedToken } from "./TimeLockedToken.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


/**
 * @title BABLToken
 * @dev The BABLToken contract is a ownable contract where the
 * owner can only mint or transfer ownership. BABLToken use 18 decimals as a standard
 */

 contract BABLToken is TimeLockedToken {
    using SafeMath for uint256;
    using Address for address;

    /* ============ Events ============ */

    /// @notice An event that emitted when a new mint ocurr
    event mintedNewTokens(address account, uint256 tokensminted);
    
    /// @notice An event thats emitted when MAX_SUPPLY changes
    event MaxSupplyChanged(uint256 previousMaxValue, uint256 newMaxValue);

    /// @notice An event that emitted when maxSupplyAllowedAfter changes
    event maxSupplyAllowedAfterChanged(uint previousAllowedAfterValue, uint newAllowedAfterValue);

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    /// @dev EIP-20 token name for this token
    string private constant NAME = "Babylon.Finance";

    /// @dev EIP-20 token symbol for this token
    string private constant SYMBOL = "BABL";

    /// @dev Maximum number of tokens in circulation of 1 million for the first 8 years (using 18 decimals as ERC20 standard)
    uint256 private MAX_SUPPLY = 1_000_000e18; // 

    /// @notice The timestamp after which a change on MAX_SUPPLY may occur
    uint public maxSupplyAllowedAfter;

     /// @notice Cap on the percentage of MAX_SUPPLY that can be increased at each change
    uint8 public constant maxSupplyCap = 5;

    /// @notice Cap on the percentage of totalSupply that can be minted at each mint
    uint8 public constant mintCap = 2;

    /// @notice The timestamp after which minting may occur
    uint public mintingAllowedAfter;

    /// @notice The timestamp of BABL Token deployment
    uint public BABLTokenDeploymentTimestamp;

    /// @dev First Epoch Mint where a maximum of 1 Million BABL cannot be increased (>= 8 Years)
    uint32 private firstEpochMint = 365 days * 8;

    /// @dev Minimum time between mints after
    uint32 private minimumTimeBetweenMints = 365 days;


    /* ============ Functions ============ */

    /* ============ Constructor ============ */

    /**
    * @notice Construct a new BABL token and gives ownership to sender
    */
    constructor() TimeLockedToken(NAME, SYMBOL) { // TODO - CHECK
        //mintingAllowedAfter = block.timestamp.add(5 minutes); TODO - USE IT BACK IN PRODUCTION
        mintingAllowedAfter = block.timestamp;

        // Timestamp of contract deployment
        BABLTokenDeploymentTimestamp = block.timestamp;
        
        // Set-up the minimum time of 8 years to wait until the MAX_SUPPLY can be changed (it will also include a max cap)
        maxSupplyAllowedAfter = block.timestamp.add(365 days * 8);
        
        //Starting with a MAX_SUPPLY of 1 million for the first 8 years
        _mint(msg.sender, 1_000_000e18);
    }

    /* ============ External Functions ============ */

    /* ===========  Token related Gov Functions ====== */


    /**
    * PRIVILEGED GOVERNANCE FUNCTION. Allows to mint new tokens
    *
    * @notice Mint new BABL tokens. Initial 1 Million BABL. After 8 years new BABL could be minted by governance decision
    * @param _to The address of the destination account that will receive the new BABL tokens
    * @param _amount The number of tokens to be minted
    *
    */
    function mint(address _to, uint256 _amount) external onlyOwner returns(bool){
        require(totalSupply().add(_amount)<= MAX_SUPPLY, "BABL::mint: max supply exceeded");
        require(block.timestamp >= BABLTokenDeploymentTimestamp.add(firstEpochMint), "BABL::mint: minting not allowed after the firstEpochMint passed >= 8 years");
        require(_amount>0, "BABL::mint: mint should be higher than zero");
        require(block.timestamp >= mintingAllowedAfter, "BABL::mint: minting not allowed yet");
        require(_to != address(0), "BABL::mint: cannot transfer to the zero address");
        require(_to != address(this),"BABL::mint: cannot mint to the address of this contract");

        // set-up the new time where a new mint can be allowed
        mintingAllowedAfter = block.timestamp.add(minimumTimeBetweenMints);

        // mint the amount 
        uint96 amount = safe96(_amount, "BABL::mint: amount exceeds 96 bits"); // TODO CHECK NUMBER OF BITS FOR OVERFLOW

        // New BABL tokens beyond initial 1 Million cannot be minted until 8 years passed, then a mintcap applies
        require(amount <= totalSupply().mul(mintCap).div(100), "BABL::mint: exceeded mint cap");
        _mint(_to, amount);
        
        emit mintedNewTokens(_to, amount);

        // move delegates
        _moveDelegates(address(0), delegates[_to], amount);
        
        return true;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to change MAX_SUPPLY
     *
     * @notice Set-up a greater MAX_SUPPLY value to allow more tokens to be minted
     * @param newMaxSupply The new maximum limit, limited by a 5% cap a year
     * @param newMaxSupplyAllowedAfter The new waiting period to change the MAX_SUPPLY limited for a minimum of 1 year
     */
    function changeMaxSupply(uint256 newMaxSupply, uint newMaxSupplyAllowedAfter) external returns(bool){
        require(block.timestamp >= BABLTokenDeploymentTimestamp.add(firstEpochMint), "BABL::changeMaxSupply: a change on MAX_SUPPLY not allowed until 8 years after deployment");
        require(block.timestamp >= maxSupplyAllowedAfter, "BABL::changeMaxSupply: a change on MAX_SUPPLY not allowed yet");
        require(newMaxSupply > MAX_SUPPLY, "BABL::changeMaxSupply: changeMaxSupply should be higher than previous value");

        // update the amount
        uint96 amount = safe96(newMaxSupply, "BABL::changeMaxSupply: new max amount exceeds 96 bits"); // TODO CHECK NUMBER OF BITS FOR OVERFLOW
        require(amount <= MAX_SUPPLY.add(MAX_SUPPLY.mul(maxSupplyCap).div(100)), "BABL::changeMaxSupply: exceeded max supply cap allowed");
        emit MaxSupplyChanged(MAX_SUPPLY, amount);
        MAX_SUPPLY = safe96(amount, "BABL::changeMaxSupply: MAX_SUPPLY exceeds 96 bits");


        // update the new waiting time until a new change could be done >= 1 year since this change
        require(newMaxSupplyAllowedAfter >= block.timestamp.add(365 days), "BABL::changeMaxSupply: the newMaxSupplyAllowedAfter should be at least 1 year in the future");
        emit maxSupplyAllowedAfterChanged(maxSupplyAllowedAfter, newMaxSupplyAllowedAfter);
        maxSupplyAllowedAfter = newMaxSupplyAllowedAfter;
        
        return true;
    }

    function maxSupply() public view returns(uint256) {
        return MAX_SUPPLY;
    }

}
