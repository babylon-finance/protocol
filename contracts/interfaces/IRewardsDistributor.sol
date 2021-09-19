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
 * Interface for the distribute rewards of the BABL Mining Program.
 */

interface IRewardsDistributor {
    // Structs
    struct PrincipalPerTimestamp {
        uint256 principal;
        uint256 time;
        uint256 timeListPointer;
    }

    /* ========== View functions ========== */

    // solhint-disable-next-line
    function START_TIME() external view returns (uint256);

    function getStrategyPricePerTokenUnit(address _strategy) external view returns (uint256, uint256);

    function getStrategyRewards(address _strategy) external view returns (uint96);

    function getRewards(
        address _garden,
        address _contributor,
        address[] calldata _finalizedStrategies
    ) external view returns (uint256[] memory);

    function getContributorPower(
        address _garden,
        address _contributor,
        uint256 _from,
        uint256 _to
    ) external view returns (uint256);

    function getGardenProfitsSharing(address _garden) external view returns (uint256[3] memory);

    function tokenSupplyPerQuarter(uint256 quarter) external view returns (uint96);

    /**
    function checkProtocol(uint256 _time)
        external
        view
        returns (
            uint256 principal,
            uint256 time,
            uint256 quarterBelonging,
            uint256 timeListPointer,
            uint256 power
        );
    */
    function checkQuarterPower(uint256 _num) external view returns (uint256 quarterPower);

    function checkStrategy(uint256 _num, address _strategy)
        external
        view
        returns (
            uint256,
            bool,
            uint256,
            uint256,
            uint256
        );

    /* ============ External Functions ============ */

    function startBABLRewards() external;

    function sendTokensToContributor(address _to, uint256 _amount) external;

    function setProfitRewards(
        address _garden,
        uint256 _strategistShare,
        uint256 _stewardsShare,
        uint256 _lpShare
    ) external;

    function updateProtocolPrincipal(uint256 _capital, bool _addOrSubstract) external;

    function updateGardenPowerAndContributor(
        address _garden,
        address _contributor,
        uint256 _previousBalance,
        uint256 _previousSupply
    ) external;

    function getGardenBetaMigrationData(address _garden)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            bool
        );

    function getContributorBetaMigrationData(address _garden, address _contributor)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            bool
        );
}
