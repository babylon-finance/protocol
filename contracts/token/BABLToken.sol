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
 * @title BABL Token
 * @dev The BABLToken contract is ERC20 using 18 decimals as a standard
 * Is Ownable to transfer ownership to Governor Alpha for Decentralized Governance 
 * It overrides the mint and maximum supply to control the timing and maximum cap allowed along the time. 
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

     /// @notice Cap on the percentage of MAX_SUPPLY that can be increased per year after maxSupplyAllowedAfter
    uint8 public constant maxSupplyCap = 5;

    /// @notice Cap on the percentage of totalSupply that can be minted at each mint after the initial 1 Million BABL
    uint8 public constant mintCap = 2;

    /// @notice The timestamp after which minting may occur after firstEpochMint (8 years)
    uint public mintingAllowedAfter;

    /// @notice The timestamp of BABL Token deployment
    uint public BABLTokenDeploymentTimestamp;

    /// @dev First Epoch Mint where no more than 1 Million BABL can be minted (>= 8 Years)
    uint32 private firstEpochMint = 365 days * 8;

    /// @dev Minimum time between mints after
    uint32 private minimumTimeBetweenMints = 365 days;


    /* ============ Functions ============ */

    /* ============ Constructor ============ */

    /**
    * @notice Construct a new BABL token and gives ownership to sender
    */
    constructor() TimeLockedToken(NAME, SYMBOL) { // TODO - CHECK


        // Timestamp of contract deployment
        BABLTokenDeploymentTimestamp = block.timestamp;
        
        // Set-up the minimum time of 8 years to wait until the MAX_SUPPLY can be changed (it will also include a max cap)
        maxSupplyAllowedAfter = block.timestamp.add(firstEpochMint);
        
        //Starting with a MAX_SUPPLY of 1 million for the first 8 years
        _mint(msg.sender, 1_000_000e18);
        
        //Set-up the minimum time of 8 years for additional mints 
        mintingAllowedAfter = block.timestamp.add(firstEpochMint);
    }

    /* ============ External Functions ============ */

    /* ===========  Token related Gov Functions ====== */


    /**
    * PRIVILEGED GOVERNANCE FUNCTION. Allows to mint new tokens
    *
    * @notice Mint new BABL tokens. Initial 1 Million BABL. After 8 years new BABL could be minted by governance decision
    * @dev mintCap The new maximum limit, limited by a 2% cap of totalSupply for each new mint and always limited by MAX_SUPPLY.
    * mintingAllowedAfter Defines the next time allowed for a new mint
    * @param _to The address of the destination account that will receive the new BABL tokens
    * @param _amount The number of tokens to be minted
    * @return Whether or not the mint succeeded
    */
    function mint(address _to, uint256 _amount) external onlyOwner returns(bool){
        require(totalSupply().add(_amount)<= MAX_SUPPLY, "BABLToken::mint: max supply exceeded");
        require(block.timestamp >= BABLTokenDeploymentTimestamp.add(firstEpochMint), "BABLToken::mint: minting not allowed after the firstEpochMint passed >= 8 years");
        require(_amount>0, "BABLToken::mint: mint should be higher than zero");
        require(block.timestamp >= mintingAllowedAfter, "BABLToken::mint: minting not allowed yet because mintingAllowedAfter");
        require(_to != address(0), "BABLToken::mint: cannot transfer to the zero address");
        require(_to != address(this),"BABLToken::mint: cannot mint to the address of this contract");

        // set-up the new time where a new (the next) mint can be allowed
        mintingAllowedAfter = block.timestamp.add(minimumTimeBetweenMints);

        // mint the amount 
        uint96 amount = safe96(_amount, "BABLToken::mint: amount exceeds 96 bits"); 

        // After firstEpochMint (8 years) a mintcap applies
        require(amount <= totalSupply().mul(mintCap).div(100), "BABLToken::mint: exceeded mint cap of 2% of total supply");
        _mint(_to, amount);
        
        emit mintedNewTokens(_to, amount);

        // move delegates
        _moveDelegates(address(0), delegates[_to], amount); // TODO - CHECK IF IT IS FINALLY NEEDED FOR VOTING POWER
        
        return true;
    }

    /**
    * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to change MAX_SUPPLY
    *
    * @notice Set-up a greater MAX_SUPPLY value to allow more tokens to be minted
    * @param newMaxSupply The new maximum limit, limited by a maximum of 5% cap per year
    * @param newMaxSupplyAllowedAfter The new waiting period to change the MAX_SUPPLY limited for a minimum of 1 year
    * @return Whether or not the changeMaxSupply succeeded
    */
    function changeMaxSupply(uint256 newMaxSupply, uint newMaxSupplyAllowedAfter) external returns(bool){
        require(block.timestamp >= BABLTokenDeploymentTimestamp.add(firstEpochMint), "BABLToken::changeMaxSupply: a change on MAX_SUPPLY not allowed until 8 years after deployment");
        require(block.timestamp >= maxSupplyAllowedAfter, "BABLToken::changeMaxSupply: a change on MAX_SUPPLY not allowed yet");

        // update the amount
        uint96 amount = safe96(newMaxSupply, "BABLToken::changeMaxSupply: new max amount exceeds 96 bits"); // Overflow check
        require(amount > MAX_SUPPLY, "BABLToken::changeMaxSupply: changeMaxSupply should be higher than previous value");
        uint96 limitedNewSupply = safe96(MAX_SUPPLY.add(MAX_SUPPLY.mul(maxSupplyCap).div(100)), "BABLToken::changeMaxSupply: potential max amount exceeds 96 bits");
        require(amount <= limitedNewSupply, "BABLToken::changeMaxSupply: exceeded of allowed 5% cap");
        emit MaxSupplyChanged(MAX_SUPPLY, amount);
        MAX_SUPPLY = amount;


        // update the new waiting time until a new change could be done >= 1 year since this change
        uint96 time = safe96(newMaxSupplyAllowedAfter, "BABLToken::changeMaxSupply: new newMaxSupplyAllowedAfter exceeds 96 bits"); // Overflow check
        uint96 futureTime = safe96(block.timestamp.add(365 days), "BABLToken::changeMaxSupply: minimum future time exceeds 96 bits"); // Overflow check
        require(time >= futureTime, "BABLToken::changeMaxSupply: the newMaxSupplyAllowedAfter should be at least 1 year in the future");
        emit maxSupplyAllowedAfterChanged(maxSupplyAllowedAfter, time);
        maxSupplyAllowedAfter = time;
        
        return true;
    }

    /**
    * PUBLIC FUNCTION. Get the value of MAX_SUPPLY
    *
    * @return Returns the value of MAX_SUPPLY at the time
    */
    function maxSupply() public view returns(uint96) {
        uint96 safeMaxSupply = safe96(MAX_SUPPLY, "BABLToken::maxSupply: MAX_SUPPLY exceeds 96 bits"); // Overflow check
        return safeMaxSupply;
    }

}
