/*
    Copyright 2020 Babylon Finance

    Modified from (Set Protocol FundValuer)

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
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/SafeCast.sol";
import { SignedSafeMath } from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { IBabController } from "./interfaces/IBabController.sol";
import { IFund } from "./interfaces/IFund.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { PreciseUnitMath } from "./lib/PreciseUnitMath.sol";

/**
 * @title ReservePool
 * @author Babylon Finance
 *
 * Contract that holds the reserve pool of the protocol.
 * The reserve pool of the protocol is used to provide liquidity to community depositors.
 * The reserve pool gets a discount for this liquidity provisioning.
 *
 */
contract ReservePool is ERC20 {
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;
    using SafeCast for int256;
    using SafeCast for uint256;
    using SignedSafeMath for int256;
    using SafeMath for uint256;

    /* ============ State Variables ============ */

    // Instance of the Controller contract
    address public controller;

    mapping(address => uint256) public communityTokenBalances; // Balances of tokens per community
    uint256 public wethBalance;

    /* ============ Constructor ============ */

    /**
     * Set state variables and map asset pairs to their oracles
     *
     * @param _controller             Address of controller contract
     */
    constructor(address _controller) {
        controller = _controller;
    }

    /* ============ External Functions ============ */

    function sellTokensToLiquidityPool(address _community, uint256 _amount) external onlyCommunity {

    }

    function withdrawWETHFromCommunityTokens() external onlyProtocol {

    }

}
