/*
    Copyright 2020 Babylon Finance

    Modified from (Set Protocol SetValuer)

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
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IBabController } from "./interfaces/IBabController.sol";

/**
 * @title Treasury
 * @author Babylon Finance
 *
 * Contract that will receive the fees earned by the protocol.
 * Governance will be able to send funds from the treasury.
 */
contract Treasury is Ownable {

    /* ============ Events ============ */

    event TreasuryFundsSent(address _asset, uint256 _amount , address _to);

    /* ============ State Variables ============ */

    // Address of the Controller contract
    IBabController public controller;

    /* ============ Constructor ============ */

    /**
     * Sets the protocol controller
     *
     * @param _controller         Address of controller contract
     */
    constructor(
      IBabController _controller
    ) {
        controller = _controller;
    }

    /* ============ External Functions ============ */

    /**
     * GOVERNANCE FUNCTION: Send an asset amount to an address
     *
     * @param _asset            Address of the asset to send
     * @param _amount           Amount to send of the asset
     * @param _to               Address to send the assets to
     */
    function sendTreasuryFunds(address _asset, uint256 _amount, address _to) external onlyOwner {
      require(_asset != address(0), "Asset must exist");
      require(_to != address(0), "Target address must exist");
      require(IERC20(_asset).balanceOf(address(this)) >= _amount, "Not enough funds in treasury");
      require(IERC20(_asset).transferFrom(
        address(this),
        _to,
        _amount
      ), "Ideator perf fee failed");
      emit TreasuryFundsSent(_asset, _amount, _to);
    }

    // Can receive ETH
    receive() external payable {} // solium-disable-line quotes
}
