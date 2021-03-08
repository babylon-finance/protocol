/*
    Copyright 2020 Babylon Finance.

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
 * @title IBabController
 * @author Babylon Finance
 *
 * Interface for interacting with BabController
 */

interface IBabController {

    /* ============ Functions ============ */

    function addCommunity(address _community) external;
    function removeCommunity(address _community) external;
    function addReserveAsset(address _reserveAsset) external;
    function removeReserveAsset(address _reserveAsset) external;
    function disableCommunity(address _community) external;
    function reenableCommunity(address _community) external;
    function editPriceOracle(address _priceOracle) external;
    function editReservePool(address _reservePool) external;
    function editCommunityValuer(address _communityValuer) external;
    function editTreasury(address _newTreasury) external;
    function addIntegration(string memory _name, address _integration) external;
    function editIntegration(string memory _name, address _integration) external;
    function removeIntegration(string memory _name) external;
    function addKeeper(address _keeper) external;
    function addKeepers(address[] memory _keepers) external;
    function removeKeeper(address _keeper) external;
    function editLiquidityMinimum(uint256 _minRiskyPairLiquidityEth) external;

    // Getters
    function owner() external view returns (address);
    function protocolReservePoolDiscount() external view returns (uint256);
    function getPriceOracle() external view returns (address);
    function getReservePool() external view returns (address);
    function getCommunityValuer() external view returns(address);
    function getTreasury() external view returns(address);
    function getCommunities() external view returns (address[] memory);
    function isCommunity(address _community) external view returns(bool);
    function getIntegrationByName(string memory _name) external view returns (address);
    function getIntegrationFee(address _integration) external view returns (uint256);
    function getIntegrationWithHash(bytes32 _nameHashP) external view returns (address);
    function isValidReserveAsset(address _reserveAsset) external view returns(bool);
    function isValidKeeper(address _keeper) external view returns (bool);
    function isSystemContract(address _contractAddress) external view returns (bool);
    function isValidIntegration(string memory _name, address _integration) external view returns (bool);
    function getMinCooldownPeriod() external view returns (uint256);
    function getMaxCooldownPeriod() external view returns (uint256);
    function getProtocolPerformanceFee() external view returns (uint256);
    function getProtocolDepositCommunityTokenFee() external view returns (uint256);
    function getProtocolWithdrawalCommunityTokenFee() external view returns (uint256);
    function minRiskyPairLiquidityEth() external view returns(uint256);
    function getUniswapFactory() external view returns(address);
}
