// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

/**
 * @title IBorrowIntegration
 * @author Babylon Finance
 *
 * Interface for borrow integrations
 */
interface IBorrowIntegration {
    function borrow(
        address _strategy,
        address asset,
        uint256 borrowAmount
    ) external;

    function repay(
        address _strategy,
        address asset,
        uint256 amount
    ) external;

    function updateMaxCollateralFactor(uint256 _newMaxCollateralFactor) external;

    function maxCollateralFactor() external view returns (uint256);

    function getCollateralFactor(address _asset) external view returns (uint256);

    function getBorrowBalance(address _strategy, address _asset) external view returns (uint256);

    function getCollateralBalance(address _strategy, address asset) external view returns (uint256);

    function getRemainingLiquidity(address _strategy) external view returns (uint256);
}
