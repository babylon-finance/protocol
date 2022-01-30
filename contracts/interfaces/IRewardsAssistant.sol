/*
    Copyright 2021 Babylon Finance.

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
 * @title IRewardsAssistant
 * @author Babylon Finance
 *
 * Interface for the rewards distributor assistant in charge of the BABL Mining Program.
 */

interface IRewardsAssistant {
    /* ========== State variables ========== */

    /* ========== View functions ========== */

    function getRewards(
        address _garden,
        address _contributor,
        address[] calldata _finalizedStrategies
    ) external view returns (uint256[] memory);

    function estimateUserRewards(address _strategy, address _contributor) external view returns (uint256[] memory);

    function estimateStrategyRewards(address _strategy) external view returns (uint256);

    function getBenchmarkRewards(
        uint256 _returned,
        uint256 _allocated,
        uint256 _rewards,
        uint256 _executedAt
    ) external view returns (uint256);

    /* ============ External Functions ============ */
}
