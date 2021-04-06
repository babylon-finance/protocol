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
pragma solidity 0.7.4;

/**
 * @title IBabController
 * @author Babylon Finance
 *
 * Interface for interacting with BabController
 */
interface IBabController {
    /* ============ Functions ============ */

    function createRollingGarden(
        address _weth,
        string memory _name,
        string memory _symbol
    ) external returns (address);

    function removeGarden(address _garden) external;

    function addReserveAsset(address _reserveAsset) external;

    function removeReserveAsset(address _reserveAsset) external;

    function disableGarden(address _garden) external;

    function reenableGarden(address _garden) external;

    function editPriceOracle(address _priceOracle) external;

    function editGardenValuer(address _gardenValuer) external;

    function editRewardsDistributor(address _rewardsDistributor) external;

    function editTreasury(address _newTreasury) external;

    function editGardenFactory(address _newGardenFactory) external;

    function editStrategyFactory(uint8 _strategyKind, address _newStrategyFactory) external;

    function addIntegration(string memory _name, address _integration) external;

    function editIntegration(string memory _name, address _integration) external;

    function removeIntegration(string memory _name) external;

    function addKeeper(address _keeper) external;

    function addKeepers(address[] memory _keepers) external;

    function removeKeeper(address _keeper) external;

    function enableGardenTokensTransfers() external;

    function editLiquidityMinimum(uint256 _minRiskyPairLiquidityEth) external;

    // Getters
    function owner() external view returns (address);

    function gardenTokensTransfersEnabled() external view returns (bool);

    function getPriceOracle() external view returns (address);

    function getRewardsDistributor() external view returns (address);

    function getGardenValuer() external view returns (address);

    function getTreasury() external view returns (address);

    function getStrategyFactory(uint8 _strategyKind) external view returns (address);

    function getGardenFactory() external view returns (address);

    function getGardens() external view returns (address[] memory);

    function isGarden(address _garden) external view returns (bool);

    function getIntegrationByName(string memory _name) external view returns (address);

    function getIntegrationFee(address _integration) external view returns (uint256);

    function getIntegrationWithHash(bytes32 _nameHashP) external view returns (address);

    function isValidReserveAsset(address _reserveAsset) external view returns (bool);

    function isValidKeeper(address _keeper) external view returns (bool);

    function isSystemContract(address _contractAddress) external view returns (bool);

    function isValidIntegration(string memory _name, address _integration) external view returns (bool);

    function getMinCooldownPeriod() external view returns (uint256);

    function getMaxCooldownPeriod() external view returns (uint256);

    function getProtocolPerformanceFee() external view returns (uint256);

    function getProtocolManagementFee() external view returns (uint256);

    function getProtocolDepositGardenTokenFee() external view returns (uint256);

    function getProtocolWithdrawalGardenTokenFee() external view returns (uint256);

    function minRiskyPairLiquidityEth() external view returns (uint256);

    function getUniswapFactory() external view returns (address);
}
