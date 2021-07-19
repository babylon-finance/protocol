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
 * @title IBabylonViewer
 * @author Babylon Finance
 *
 * Viewer Interface.
 */

interface IBabylonViewer {
    function controller() external view returns (address);

    function getGardenDetails(address _garden)
        external
        view
        returns (
            string memory,
            string memory,
            address,
            address,
            bool[4] memory,
            address[] memory,
            address[] memory,
            uint256[10] memory,
            uint256[9] memory,
            uint256[3] memory
        );

    function getCompleteStrategy(address _strategy)
        external
        view
        returns (
            address,
            string memory,
            uint256[12] memory,
            bool[] memory,
            uint256[] memory
        );

    function getPermissions(address _user) external view returns (bool, bool);

    function getGardenPermissions(address _garden, address _user)
        external
        view
        returns (
            bool,
            bool,
            bool
        );

    function getGardensUser(address _user, uint256 _offset) external view returns (address[] memory, bool[] memory);

    function getUserStrategyActions(address[] memory _strategies, address _user)
        external
        view
        returns (uint256, uint256);

    function getContributionAndRewards(address _garden, address _user)
        external
        view
        returns (uint256[] memory, uint256[] memory);
}
