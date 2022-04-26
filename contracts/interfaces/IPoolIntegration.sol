// SPDX-License-Identifier: Apache-2.0

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

    function getPoolTokens(bytes calldata _pool, bool forNAV) external view returns (address[] memory);

    function getPoolWeights(bytes calldata _pool) external view returns (uint256[] memory);

    function getLPToken(address _pool) external view returns (address);

    function getPool(address _pool) external view returns (address);

    function totalSupply(address _pool) external view returns (uint256);

    function getUnderlyingAndRate(bytes calldata _pool, uint256 _i) external view returns (address, uint256);

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

    function poolWeightsByPrice(bytes calldata _pool) external view returns (bool);

    function getRewardTokens(bytes calldata _pool) external view returns (address[] memory);
}
