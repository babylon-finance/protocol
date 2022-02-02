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
    /* ========== State variables ========== */

    function bablPrincipalWeight() external view returns (uint256);

    function bablProfitWeight() external view returns (uint256);

    /* ========== View functions ========== */

    function getBenchmark() external view returns (uint256[5] memory);

    function getStrategyRewards(address _strategy) external view returns (uint256);

    function getUserRewardsNonce(address _user) external view returns (uint256);

    function getRewards(
        address _garden,
        address _contributor,
        address[] calldata _finalizedStrategies
    ) external view returns (uint256[] memory);

    function estimateUserRewards(address _strategy, address _contributor) external view returns (uint256[] memory);

    function estimateStrategyRewards(address _strategy) external view returns (uint256);

    function getGardenProfitsSharing(address _garden) external view returns (uint256[3] memory);

    function getSafeUserSharePerStrategy(
        address _garden,
        address _contributor,
        address _strategy
    ) external view returns (uint256);

    function checkMining(uint256 _quarterNum, address _strategy) external view returns (uint256[18] memory);

    function getInitialStrategyPower(
        address _strategy,
        uint256 _numQuarters,
        uint256 _startingQuarter
    ) external view returns (uint256[] memory, uint256[] memory);

    function getRoleWeights(address _garden) external view returns (uint256[7] memory roleWeights);

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

    function claimRewards(address _garden, address[] calldata _finalizedStrategies) external;

    function claimAllRewards(address[] memory _myGardens) external;

    function claimRewardsBySig(
        address _garden,
        uint256 _babl,
        uint256 _profits,
        uint256 _rewardsUserNonce,
        uint256 _maxFee,
        uint256 _fee,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function claimAllRewardsBySig(
        address[] memory _gardens,
        uint256[] memory _babl,
        uint256[] memory _profits,
        uint256[] memory _signatureData,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function setRewardsAssistant(address _newRewardsAssistant) external;

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
}
