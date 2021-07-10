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
 * @title IPoolIntegration
 * @author Babylon Finance
 *
 * Interface for liquiditypool protocol integrations
 */
interface IPoolIntegration {
    function joinPool(
        address _strategy,
        bytes calldata _pool,
        uint256 _poolTokensOut,
        address[] memory _poolTokens,
        uint256[] memory _maxAmountsIn
    ) external;

    function exitPool(
        address _strategy,
        bytes calldata _pool,
        uint256 _poolTokensIn,
        address[] memory _poolTokens,
        uint256[] memory _minAmountsOut
    ) external;

    function getPoolTokens(bytes calldata _pool) external view returns (address[] memory);

    function getPoolWeights(bytes calldata _pool) external view returns (uint256[] memory);

    function getLPToken(bytes calldata _pool) external view returns (address);

    function getPoolTokensOut(
        bytes calldata _pool,
        address _tokenAddress,
        uint256 _maxAmountsIn
    ) external view returns (uint256);

    function getPoolMinAmountsOut(bytes calldata _pool, uint256 _poolTokenAmount)
        external
        view
        returns (uint256[] memory _minAmountsOut);

    function isPool(bytes calldata _pool) external view returns (bool);
}
