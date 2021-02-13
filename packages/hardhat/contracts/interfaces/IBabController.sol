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
    function changeFundEndDate(address _fund, uint256 _newEndTimestamp) external;
    function editPriceOracle(address _priceOracle) external;
    function editFundValuer(address _fundValuer) external;
    function editFeeRecipient(address _newFeeRecipient) external;
    function addIntegration(string memory _name, address _integration) external;
    function initializeIntegration(address _integration, address _fund) external;
    function editIntegration(string memory _name, address _integration) external;
    function removeIntegration(string memory _name) external;
    function setMinFundEpoch(uint256 _newMinFundEpoch) external;
    function setMaxFundEpoch(uint256 _newMaxFundEpoch) external;
    function setMinFundDuration(uint256 _newMinFundDuration) external;
    function setMaxFundDuration(uint256 _newMaxFundDuration) external;
    function addAssetWhitelist(address _asset) external;
    function removeAssetWhitelist(address _asset) external;
    function addAssetsWhitelist(address[] memory _assets) external;

    // Getters
    function getPriceOracle() external view returns (address);
    function getFundValuer() external view returns(address);
    function getFeeRecipient() external view returns(address);
    function getFunds() external view returns (address[] memory);
    function isFund(address _fund) external view returns(bool);
    function getIntegrationByName(string memory _name) external view returns (address);
    function getIntegrationFee(address _integration) external view returns (uint256);
    function getIntegrationWithHash(bytes32 _nameHashP) external view returns (address);
    function isValidReserveAsset(address _reserveAsset) external view returns(bool);
    function isValidAsset(address _asset) external view returns (bool);
    function isSystemContract(address _contractAddress) external view returns (bool);
    function isValidIntegration(string memory _name) external view returns (bool);
    function getMaxFundDuration() external view returns (uint256);
    function getMinFundDuration() external view returns (uint256);
    function getMaxFundEpoch() external view returns (uint256);
    function getMinFundEpoch() external view returns (uint256);
    function getMinDeliberationPeriod() external view returns (uint256);
    function getMaxDeliberationPeriod() external view returns (uint256);
    function getMaxFundPremiumPercentage() external view returns (uint256);
    function getProtocolPerformanceFee() external view returns (uint256);
    function getProtocolDepositFundTokenFee() external view returns (uint256);
    function getProtocolWithdrawalFundTokenFee() external view returns (uint256);
}
