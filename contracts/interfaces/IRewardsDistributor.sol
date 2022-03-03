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
 * @title IRewardsDistributor
 * @author Babylon Finance
 *
 * Interface for the rewards distributor in charge of the BABL Mining Program.
 */

interface IRewardsDistributor {
    /* ========== View functions ========== */

    function getStrategyRewards(address _strategy) external view returns (uint256);

    function getRewards(
        address _garden,
        address _contributor,
        address[] calldata _finalizedStrategies
    ) external view returns (uint256[] memory);

    function getGardenProfitsSharing(address _garden) external view returns (uint256[3] memory);

    function checkMining(uint256 _quarterNum, address _strategy) external view returns (uint256[17] memory);

    function estimateUserRewards(address _strategy, address _contributor) external view returns (uint256[] memory);

    function estimateStrategyRewards(address _strategy) external view returns (uint256);

    function getPriorBalance(
        address _garden,
        address _contributor,
        uint256 _timestamp
    )
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    /* ============ External Functions ============ */

    function setProfitRewards(
        address _garden,
        uint256 _strategistShare,
        uint256 _stewardsShare,
        uint256 _lpShare
    ) external;

    function migrateAddressToCheckpoints(address[] memory _garden, bool _toMigrate) external;

    function setBABLMiningParameters(uint256[11] memory _newMiningParams) external;

    function updateProtocolPrincipal(uint256 _capital, bool _addOrSubstract) external;

    function updateGardenPowerAndContributor(
        address _garden,
        address _contributor,
        uint256 _previousBalance,
        uint256 _tokenDiff,
        bool _addOrSubstract
    ) external;

    function sendBABLToContributor(address _to, uint256 _babl) external returns (uint256);
}
