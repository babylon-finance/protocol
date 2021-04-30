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

    function protocolPrincipal() external view returns (uint256);

    function pid() external view returns (uint256);

    // solhint-disable-next-line
    function EPOCH_DURATION() external pure returns (uint256);

    // solhint-disable-next-line
    function START_TIME() external view returns (uint256);

    // solhint-disable-next-line
    function Q1_REWARDS() external pure returns (uint256);

    // solhint-disable-next-line
    function DECAY_RATE() external pure returns (uint256);

    function addProtocolPrincipal(uint256 _capital) external;

    function substractProtocolPrincipal(uint256 _capital) external;

    function getStrategyRewards(address _strategy) external returns (uint96);

    function sendTokensToContributor(address _to, uint96 _amount) external;

    function getProtocolPrincipalByTimestamp(uint256 _timestamp) external view returns (uint256);

    function getProtocolPowerPerQuarterByTimestamp(uint256 _timestamp) external view returns (uint256);

    function getProtocolPowerPerQuarterById(uint256 _id) external view returns (uint256);

    function getProtocolSupplyPerQuarterByTimestamp(uint256 _timestamp) external view returns (uint256);

    function getEpochRewards(uint256 epochs) external view returns (uint96[] memory);

    function getCheckpoints() external view returns (uint256);

    function getQuarter(uint256 _now) external view returns (uint256);

    function getRewardsWindow(uint256 _from, uint256 _to) external view returns (uint256, uint256);

    function getSupplyForPeriod(uint256 _from, uint256 _to) external view returns (uint96[] memory);

    function tokenSupplyPerQuarter(uint256 quarter) external pure returns (uint96);

    function getRewards(
        address _garden,
        address _contributor,
        address[] calldata _finalizedStrategies
    ) external view returns (uint256, uint96);
    
    function getContributorPower(address _garden, address _contributor, uint256 _from, uint256 _to) external view returns (uint256);

    function getContributor(address _garden, address _contributor)
        external
        view
        returns (
            uint256,
            uint256,
            uint256[] memory,
            uint256
        );
    
    function updateGardenPower(address _garden) external;

    function setContributorTimestampParams(address _garden, address _contributor, uint256 _previousBalance, bool _depositOrWithdraw) external;

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

    function checkQuarter(uint256 _num)
        external
        view
        returns (
            uint256 quarterPrincipal,
            uint256 quarterNumber,
            uint256 quarterPower,
            uint96 supplyPerQuarter
        );
}
