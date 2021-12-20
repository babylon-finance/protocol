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
 * @title IBabController
 * @author Babylon Finance
 *
 * Interface for interacting with BabController
 */
interface IBabController {
    /* ============ Functions ============ */

    function createGarden(
        address _reserveAsset,
        string memory _name,
        string memory _symbol,
        string memory _tokenURI,
        uint256 _seed,
        uint256[] calldata _gardenParams,
        uint256 _initialContribution,
        bool[] memory _publicGardenStrategistsStewards,
        uint256[] memory _profitSharing
    ) external payable returns (address);

    function removeGarden(address _garden) external;

    function addReserveAsset(address _reserveAsset) external;

    function removeReserveAsset(address _reserveAsset) external;

    function editPriceOracle(address _priceOracle) external;

    function editMardukGate(address _mardukGate) external;

    function editGardenValuer(address _gardenValuer) external;

    function editTreasury(address _newTreasury) external;

    function editRewardsDistributor(address _rewardsDistributor) external;

    function editGardenFactory(address _newGardenFactory) external;

    function editGardenNFT(address _newGardenNFT) external;

    function editStrategyNFT(address _newStrategyNFT) external;

    function editStrategyFactory(address _newStrategyFactory) external;

    function setOperation(uint8 _kind, address _operation) external;

    function setMasterSwapper(address _newMasterSwapper) external;

    function addKeeper(address _keeper) external;

    function addKeepers(address[] memory _keepers) external;

    function removeKeeper(address _keeper) external;

    function enableGardenTokensTransfers() external;

    function editLiquidityReserve(address _reserve, uint256 _minRiskyPairLiquidityEth) external;

    function gardenCreationIsOpen() external view returns (bool);

    function owner() external view returns (address);

    function EMERGENCY_OWNER() external view returns (address);

    function guardianGlobalPaused() external view returns (bool);

    function guardianPaused(address _address) external view returns (bool);

    function setPauseGuardian(address _guardian) external;

    function setGlobalPause(bool _state) external returns (bool);

    function setSomePause(address[] memory _address, bool _state) external returns (bool);

    function isPaused(address _contract) external view returns (bool);

    function priceOracle() external view returns (address);

    function gardenValuer() external view returns (address);

    function gardenNFT() external view returns (address);

    function strategyNFT() external view returns (address);

    function rewardsDistributor() external view returns (address);

    function gardenFactory() external view returns (address);

    function treasury() external view returns (address);

    function ishtarGate() external view returns (address);

    function mardukGate() external view returns (address);

    function strategyFactory() external view returns (address);

    function masterSwapper() external view returns (address);

    function gardenTokensTransfersEnabled() external view returns (bool);

    function bablMiningProgramEnabled() external view returns (bool);

    function allowPublicGardens() external view returns (bool);

    function enabledOperations(uint256 _kind) external view returns (address);

    function getGardens() external view returns (address[] memory);

    function getOperations() external view returns (address[20] memory);

    function isGarden(address _garden) external view returns (bool);

    function isValidReserveAsset(address _reserveAsset) external view returns (bool);

    function isValidKeeper(address _keeper) external view returns (bool);

    function isSystemContract(address _contractAddress) external view returns (bool);

    function protocolPerformanceFee() external view returns (uint256);

    function protocolManagementFee() external view returns (uint256);

    function minLiquidityPerReserve(address _reserve) external view returns (uint256);
}
