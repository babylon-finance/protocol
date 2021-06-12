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

/**
 * @title IBorrowIntegration
 * @author Babylon Finance
 *
 * Interface for borrow integrations
 */
interface IBorrowIntegration {
    function borrow(
        address _strategy,
        address asset,
        uint256 borrowAmount
    ) external;

    function repay(
        address _strategy,
        address asset,
        uint256 amount
    ) external;

    function updateMaxCollateralFactor(uint256 _newMaxCollateralFactor) external;

    function maxCollateralFactor() external view returns (uint256);

    function getBorrowBalance(address _strategy, address _asset) external view returns (uint256);

    function getCollateralBalance(address _strategy, address asset) external view returns (uint256);

    function getRemainingLiquidity(address _strategy) external view returns (uint256);
}
