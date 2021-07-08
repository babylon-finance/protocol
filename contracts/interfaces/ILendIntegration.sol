/*
    Copyright 2021 Babylon Finance

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
 * @title ILendIntegration
 * @author Babylon Finance
 *
 * Interface for lending integrations such as Compound, Aave.
 */
interface ILendIntegration {
    function supplyTokens(
        address _strategy,
        address _assetToken,
        uint256 _numTokensToSupply,
        uint256 _minAmountExpected
    ) external;

    function redeemTokens(
        address _strategy,
        address _assetToken,
        uint256 _numTokensToRedeem,
        uint256 _minAmountExpected
    ) external;

    function getRewardToken() external view returns (address);

    function getRewardsAccrued(address _strategy) external view returns (uint256);

    function getExpectedShares(address _assetToken, uint256 _numTokensToSupply) external view returns (uint256);

    function getExchangeRatePerToken(address _assetToken) external view returns (uint256);

    function getInvestmentToken(address _assetToken) external view returns (address);

    function getInvestmentTokenAmount(address _address, address _assetToken) external view returns (uint256);
}
