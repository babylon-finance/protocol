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
pragma solidity 0.7.4;

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
        address _integration,
        uint256 _maxCapitalRequested,
        uint256 _stake,
        uint256 _strategyDuration,
        uint256 _expectedReturn,
        uint256 _minRebalanceCapital
    ) external;

    function resolveVoting(
        address[] calldata _voters,
        int256[] calldata _votes,
        uint256 _absoluteTotalVotes,
        int256 _totalVotes,
        uint256 fee
    ) external;

    function setData(address _data) external;

    function executeStrategy(uint256 _capital, uint256 fee) external;

    function getNAV() external view returns (uint256);

    function getLossesStrategy() external view returns (uint256);

    function finalizeStrategy(uint256 fee) external;

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

    function getStrategyDetails()
        external
        view
        returns (
            address,
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

    function isStrategyActive() external pure returns (bool);

    function getUserVotes(address _address) external view returns (int256);

    function strategist() external pure returns (address);

    function enteredAt() external pure returns (uint256);

    function enteredCooldownAt() external pure returns (uint256);

    function executedAt() external pure returns (uint256);

    function updatedAt() external pure returns (uint256);

    function exitedAt() external pure returns (uint256);

    function stake() external pure returns (uint256);

    function strategyRewards() external pure returns (uint96);

    function rewardsTotalOverhead() external pure returns (uint256);

    function maxCapitalRequested() external pure returns (uint256);

    function expectedReturn() external pure returns (uint256);

    function minRebalanceCapital() external pure returns (uint256);

    function enterTokensNeeded() external pure returns (address[] memory);

    function enterTokensAmounts() external pure returns (uint256[] memory);

    function voters() external pure returns (address[] memory);

    function duration() external pure returns (uint256);

    function totalVotes() external pure returns (int256);

    function absoluteTotalVotes() external pure returns (uint256);

    function totalVoters() external pure returns (int256);

    function integration() external pure returns (address);

    function enterPayload() external pure returns (bytes memory);

    function exitPayload() external pure returns (bytes memory);

    function capitalReturned() external pure returns (uint256);

    function capitalAllocated() external pure returns (uint256);

    function finalized() external pure returns (bool);

    function active() external pure returns (bool);

    function garden() external pure returns (address);
}
