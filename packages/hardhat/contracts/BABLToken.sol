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

    /// @notice An event thats emitted when the minter address is changed
    event MinterChanged(address minter, address newMinter);

    /// @notice An event thats emitted when MAX_SUPPLY changes
    event MaxSupplyChanged(uint256 previousMaxValue, uint256 newMaxValue);

    /// @notice An event that emitted when maxSupplyAllowedAfter changes
    event maxSupplyAllowedAfterChanged(uint previousAllowedAfterValue, uint newAllowedAfterValue);

    /// @notice An event thats emitted when minimumTimeBetweenMints changes
    event MinimumTimeBetweenMintsChanged(uint previousMintTime, uint newMintTime);

    /// @notice An event that emitted when maxSupplyAllowedAfter changes
    event TimeBetweenMintsAllowedAfterChanged(uint previousMintTimeAllowedAfterValue, uint newMintTimeAllowedAfterValue);


    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    /// @dev EIP-20 token name for this token
    string public constant NAME = "Babylon.Finance";

    /// @dev EIP-20 token symbol for this token
    string public constant SYMBOL = "BABL";

    /// @notice Total number of tokens in circulation
    uint256 public _totalSupply = 1_000_000e18; // 1 million BABL

    /// @dev Maximum number of tokens in circulation
    uint256 private MAX_SUPPLY = 1_000_000e18; // Starting with a MAX_SUPPLY of 1 million for the first 8 years

    /// @notice The timestamp after which a change on MAX_SUPPLY may occur
    uint public maxSupplyAllowedAfter;

     /// @notice Cap on the percentage of MAX_SUPPLY that can be increased at each change
    uint8 public maxSupplyCap = 5;

    /// @notice Cap on the percentage of totalSupply that can be minted at each mint
    uint8 public constant mintCap = 2;

    /// @notice The timestamp after which minting may occur
    uint public mintingAllowedAfter;

    /// @notice The timestamp of BABL Token deployment
    uint public BABLTokenDeploymentTimestamp;

    /// @notice First Epoch Mint with a maximum of 1 Million BABL (>= 8 Years)
    uint32 public firstEpochMint = 52 weeks * 8;

    /// @notice Minimum time between mints after
    uint32 public minimumTimeBetweenMints;

    /// @notice Minimum time between changes on mint parameters
    uint public ChangeTimeBetweenMintsAllowedAfter;




    /* ============ Functions ============ */

    /* ============ Constructor ============ */

    /**
    * @notice Construct a new BABL token and gives ownership to sender
    */
    constructor() TimeLockedToken(NAME, SYMBOL) { // TODO - CHECK
        mintingAllowedAfter = block.timestamp.add(5 minutes);
        minimumTimeBetweenMints = 1 days * 365;
        ChangeTimeBetweenMintsAllowedAfter = block.timestamp.add(52 weeks);
        BABLTokenDeploymentTimestamp = block.timestamp;
        maxSupplyAllowedAfter = block.timestamp.add(52 weeks * 8);

    }

    /* ============ External Functions ============ */

    /* ===========  Token related Gov Functions ====== */

    /**
     * @notice Get the number of totalSupply tokens
     * @return The number of totalSupply BABL tokens
     */

    function totalSupply() public view override returns (uint256) { // TODO - CHECK
        return _totalSupply;
    }

    /**
    * PRIVILEGED GOVERNANCE FUNCTION. Allows to mint new tokens
    *
    * @notice Mint new BABL tokens. Initial 1 Million BABL. After 8 years new BABL could be minted by governance decision
    * @param _to The address of the destination account that will receive the new BABL tokens
    * @param _amount The number of tokens to be minted
    *
    */
    function mint(address _to, uint256 _amount) external onlyOwner nonReentrant {
        require(_totalSupply.add(_amount)<= MAX_SUPPLY, "BABL::mint: max supply exceeded");
        require(_amount>0, "BABL::mint: mint should be higher than zero");
        require(block.timestamp >= mintingAllowedAfter, "BABL::mint: minting not allowed yet");
        require(_to != address(0), "BABL::mint: cannot transfer to the zero address");

        // record the mint
        mintingAllowedAfter = block.timestamp.add(minimumTimeBetweenMints);

        // mint the amount
        uint96 amount = safe96(_amount, "BABL::mint: amount exceeds 96 bits");

        if (block.timestamp >= BABLTokenDeploymentTimestamp.add(firstEpochMint)) {
            // New BABL tokens beyond initial 1 Million cannot be minted until 8 years passed, then a mintcap applies
            require(amount <= _totalSupply.mul(mintCap).div(100), "BABL::mint: exceeded mint cap"); // TODO - IMPLEMENT THE CAP LIMIT ONLY AFTER 8 YEARS
            _mint(_to, amount);
        }
        else {
        _mint(_to, amount);
        }

        // move delegates
        _moveDelegates(address(0), delegates[_to], amount);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to change MAX_SUPPLY
     *
     * @notice Set-up a greater MAX_SUPPLY value to allow more tokens to be minted
     * @param newMaxSupply The new maximum limit, limited by a 5% cap a year
     * @param newMaxSupplyAllowedAfter The new waiting period to change the MAX_SUPPLY limited for a minimum of 1 year
     */
    function changeMaxSupply(uint256 newMaxSupply, uint newMaxSupplyAllowedAfter) external {
        require(block.timestamp >= BABLTokenDeploymentTimestamp.add(firstEpochMint), "BABL::changeMaxSupply: a change on MAX_SUPPLY not allowed until 8 years after deployment");
        require(block.timestamp >= maxSupplyAllowedAfter, "BABL::changeMaxSupply: a change on MAX_SUPPLY not allowed yet");
        require(newMaxSupply > MAX_SUPPLY, "BABL::changeMaxSupply: changeMaxSupply should be higher than previous value");

        // update the amount
        uint96 amount = safe96(newMaxSupply, "BABL::changeMaxSupply: new max amount exceeds 96 bits");
        require(amount <= MAX_SUPPLY.add(MAX_SUPPLY.mul(maxSupplyCap).div(100)), "BABL::changeMaxSupply: exceeded max supply cap");
        emit MaxSupplyChanged(MAX_SUPPLY, amount);
        MAX_SUPPLY = safe96(amount, "BABL::changeMaxSupply: MAX_SUPPLY exceeds 96 bits");


        // update the new waiting time until a new change could be done
        require(newMaxSupplyAllowedAfter > block.timestamp.add(365 days), "BABL::changeMaxSupply: the newMaxSupplyAllowedAfter should be at least 1 year in the future");
        emit maxSupplyAllowedAfterChanged(maxSupplyAllowedAfter, newMaxSupplyAllowedAfter);
        maxSupplyAllowedAfter = newMaxSupplyAllowedAfter;
    }

     /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to change minimumTimeBetweenMints
     *
     * @notice Modify minimumTimeBetweenMints value to allow a change on the allowed frequency between mints
     * @param newTimeBetweenMints The new limit
     * @param newTimeBetweenMintsAllowedAfter The new waiting period to change the minimumTimeBetweenMints
     */
    function changeTimeBetweenMints(uint newTimeBetweenMints, uint newTimeBetweenMintsAllowedAfter) external {
        require(block.timestamp >= ChangeTimeBetweenMintsAllowedAfter, "BABL::changeTimeBetweenMints: a change on minimumTimeBetweenMints not allowed yet");

        // update the amount
        require(newTimeBetweenMints > 30 days, "BABL::mint: time between mints should be higher than 30 days");
        uint96 amount = safe32(newTimeBetweenMints, "BABL::changeTimeBetweenMints: new amount exceeds 32 bits");
        emit MinimumTimeBetweenMintsChanged(minimumTimeBetweenMints, amount);
        minimumTimeBetweenMints = safe32(amount, "BABL::changeTimeBetweenMints: new amount exceeds 32 bits");


        // update the new waiting time until a new change could be done
        uint96 amountAllowedAfter = safe32(newTimeBetweenMintsAllowedAfter, "BABL::changeTimeBetweenMints: new amountAllowedAfter exceeds 32 bits");
        emit TimeBetweenMintsAllowedAfterChanged(ChangeTimeBetweenMintsAllowedAfter, amountAllowedAfter);
        ChangeTimeBetweenMintsAllowedAfter = safe32(amountAllowedAfter,"BABL::changeTimeBetweenMints: new amountAllowedAfter exceeds 32 bits");
    }
}
