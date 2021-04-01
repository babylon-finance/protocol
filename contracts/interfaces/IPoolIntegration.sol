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
pragma solidity 0.7.4;

import {IIntegration} from './IIntegration.sol';

/**
 * @title IIntegration
 * @author Babylon Finance
 *
 * Interface for liquiditypool protocol integrations
 */
interface IPoolIntegration is IIntegration {
    function joinPool(
        address _poolAddress,
        uint256 _poolTokensOut,
        address[] calldata _tokensIn,
        uint256[] calldata _maxAmountsIn
    ) external;

    function exitPool(
        address _poolAddress,
        uint256 _poolTokensIn,
        address[] calldata _tokensOut,
        uint256[] calldata _minAmountsOut
    ) external;

    function getPoolTokens(address _poolAddress) external view returns (address[] memory);

    function getPoolWeights(address _poolAddress) external view returns (uint256[] memory);

    function isPool(address _poolAddress) external view returns (bool);
}
