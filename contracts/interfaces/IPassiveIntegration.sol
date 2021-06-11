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
 * @title IPassiveIntegration
 * @author Babylon Finance
 *
 * Interface for passive investments protocol integrations
 */
interface IPassiveIntegration {
    function enterInvestment(
        address _strategy,
        address _investmentAddress,
        uint256 _investmentTokensOut,
        address _tokenIn,
        uint256 _maxAmountIn
    ) external;

    function exitInvestment(
        address _strategy,
        address _investmentAddress,
        uint256 _investmentTokenIn,
        address _tokenOut,
        uint256 _minAmountOut
    ) external;

    function getExpectedShares(address _investmentAddress, uint256 _ethAmount) external view returns (uint256);

    function getPricePerShare(address _investmentAddress) external view returns (uint256);

    function getInvestmentAsset(address _investmentAddress) external view returns (address);
}
