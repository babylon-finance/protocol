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

    function addFund(address _fund) external;
    function removeFund(address _fund) external;
    function addReserveAsset(address _reserveAsset) external;
    function removeReserveAsset(address _reserveAsset) external;
    function disableFund(address _fund) external;
    function reenableFund(address _fund) external;
    function editPriceOracle(address _priceOracle) external;
    function editReservePool(address _reservePool) external;
    function editFundValuer(address _fundValuer) external;
    function editFeeRecipient(address _newFeeRecipient) external;
    function addIntegration(string memory _name, address _integration) external;
    function initializeIntegration(address _integration, address _fund) external;
    function editIntegration(string memory _name, address _integration) external;
    function removeIntegration(string memory _name) external;
    function setProtocolReservePoolDiscount(uint256 _newProtocolReservePoolDiscount) external;
    function setMinWithdrawalWindow(uint256 _newMinWithdrawalWindow) external;
    function setMaxWithdrawalWindow(uint256 _newMaxWithdrawalWindow) external;
    function setMinFundActiveWindow(uint256 _newMinFundActiveWindow) external;
    function setMaxFundActiveWindow(uint256 _newMaxFundActiveWindow) external;
    function addAssetWhitelist(address _asset) external;
    function removeAssetWhitelist(address _asset) external;
    function addAssetsWhitelist(address[] memory _assets) external;
    function addKeeper(address _keeper) external;
    function removeKeeper(address _keeper) external;
    function addKeepers(address[] memory _keepers) external;

    // Getters
    function owner() external view returns (address);
    function protocolReservePoolDiscount() external view returns (uint256);
    function getPriceOracle() external view returns (address);
    function getReservePool() external view returns (address);
    function getFundValuer() external view returns(address);
    function getFeeRecipient() external view returns(address);
    function getFunds() external view returns (address[] memory);
    function isFund(address _fund) external view returns(bool);
    function getIntegrationByName(string memory _name) external view returns (address);
    function getIntegrationFee(address _integration) external view returns (uint256);
    function getIntegrationWithHash(bytes32 _nameHashP) external view returns (address);
    function isValidReserveAsset(address _reserveAsset) external view returns(bool);
    function isValidAsset(address _asset) external view returns (bool);
    function isValidKeeper(address _keeper) external view returns (bool);
    function isSystemContract(address _contractAddress) external view returns (bool);
    function isValidIntegration(string memory _name, address _integration) external view returns (bool);
    function getMinFundActiveWindow() external view returns (uint256);
    function getMaxFundActiveWindow() external view returns (uint256);
    function getMinWithdrawalWindow() external view returns (uint256);
    function getMaxWithdrawalWindow() external view returns (uint256);
    function getMinCooldownPeriod() external view returns (uint256);
    function getMaxCooldownPeriod() external view returns (uint256);
    function getMaxFundPremiumPercentage() external view returns (uint256);
    function getProtocolPerformanceFee() external view returns (uint256);
    function getProtocolDepositFundTokenFee() external view returns (uint256);
    function getProtocolWithdrawalFundTokenFee() external view returns (uint256);
}
