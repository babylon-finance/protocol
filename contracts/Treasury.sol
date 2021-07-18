/*
    Copyright 2021 Babylon Finance

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

pragma solidity 0.7.6;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {IBabController} from './interfaces/IBabController.sol';

/**
 * @title Treasury
 * @author Babylon Finance
 *
 * Contract that will receive the fees earned by the protocol.
 * Governance will be able to send funds from the treasury.
 */
contract Treasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    /* ============ Events ============ */

    event TreasuryFundsSent(address _asset, uint256 _amount, address _to);

    /* ============ State Variables ============ */

    // Address of the Controller contract
    IBabController public controller;

    /* ============ Constructor ============ */

    /**
     * Sets the protocol controller
     *
     * @param _controller         Address of controller contract
     */
    constructor(IBabController _controller) {
        require(address(_controller) != address(0), 'Controller must exist');
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
    function sendTreasuryFunds(
        address _asset,
        uint256 _amount,
        address _to
    ) external onlyOwner nonReentrant {
        require(_asset != address(0), 'Asset must exist');
        require(_to != address(0), 'Target address must exist');

        IERC20(_asset).safeTransfer(_to, _amount);

        emit TreasuryFundsSent(_asset, _amount, _to);
    }

    /**
     * GOVERNANCE FUNCTION: Send an ETH amount to an address
     *
     * @param _amount           Amount to send of the asset
     * @param _to               Address to send the assets to
     */
    function sendTreasuryETH(uint256 _amount, address payable _to) external onlyOwner nonReentrant {
        require(_to != address(0), 'Target address must exist');
        require(address(this).balance >= _amount, 'Not enough funds in treasury');

        Address.sendValue(_to, _amount);

        emit TreasuryFundsSent(address(0), _amount, _to);
    }

    // Can receive ETH
    // solhint-disable-next-line
    receive() external payable {}
}
