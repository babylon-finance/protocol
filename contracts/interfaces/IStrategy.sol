/*
    Copyright 2021 Babylon Finance

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

import {IGarden} from '../interfaces/IGarden.sol';

/**
 * @title IStrategy
 * @author Babylon Finance
 *
 * Interface for strategy
 */
interface IStrategy {
    function initialize(
        address _strategist,
        address _garden,
        address _controller,
        uint256 _maxCapitalRequested,
        uint256 _stake,
        uint256 _strategyDuration,
        uint256 _expectedReturn
    ) external;

    function resolveVoting(
        address[] calldata _voters,
        int256[] calldata _votes,
        uint256 fee
    ) external;

    function setData(
        uint8[] calldata _opTypes,
        address[] calldata _opIntegrations,
        bytes memory _opEncodedData
    ) external;

    function executeStrategy(uint256 _capital, uint256 fee) external;

    function getNAV() external view returns (uint256);

    function opDatas(uint256 _index) external view returns (address);

    function opEncodedData() external view returns (bytes memory);

    function opIntegrations(uint256 _index) external view returns (address);

    function opTypes(uint256 _index) external view returns (uint8);

    function getOperationsCount() external view returns (uint256);

    function getOperationByIndex(uint8 _index)
        external
        view
        returns (
            uint8,
            address,
            bytes memory
        );

    function finalizeStrategy(uint256 fee, string memory _tokenURI) external;

    function unwindStrategy(uint256 _amountToUnwind) external;

    function changeStrategyDuration(uint256 _newDuration) external;

    function invokeFromIntegration(
        address _target,
        uint256 _value,
        bytes calldata _data
    ) external returns (bytes memory);

    function invokeApprove(
        address _spender,
        address _asset,
        uint256 _quantity
    ) external;

    function trade(
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken
    ) external returns (uint256);

    function handleWeth(bool _isDeposit, uint256 _wethAmount) external;

    function getStrategyDetails()
        external
        view
        returns (
            address,
            address,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            address,
            uint256,
            uint256
        );

    function getStrategyState()
        external
        view
        returns (
            address,
            bool,
            bool,
            bool,
            uint256,
            uint256,
            uint256
        );

    function isStrategyActive() external view returns (bool);

    function getUserVotes(address _address) external view returns (int256);

    function strategist() external view returns (address);

    function enteredAt() external view returns (uint256);

    function enteredCooldownAt() external view returns (uint256);

    function executedAt() external view returns (uint256);

    function updatedAt() external view returns (uint256);

    function exitedAt() external view returns (uint256);

    function stake() external view returns (uint256);

    function strategyRewards() external view returns (uint256);

    function maxCapitalRequested() external view returns (uint256);

    function expectedReturn() external view returns (uint256);

    function duration() external view returns (uint256);

    function totalPositiveVotes() external view returns (uint256);

    function totalVotes() external view returns (int256);

    function totalNegativeVotes() external view returns (uint256);

    function capitalReturned() external view returns (uint256);

    function capitalAllocated() external view returns (uint256);

    function finalized() external view returns (bool);

    function active() external view returns (bool);

    function garden() external view returns (IGarden);
}
