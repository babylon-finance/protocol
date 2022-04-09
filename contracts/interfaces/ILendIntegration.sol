// SPDX-License-Identifier: Apache-2.0

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

    function getHealthFactor(address _strategy) external view returns (uint256);

    function getRewardToken() external view returns (address);

    function getCollateralFactor(address _assetToken) external view returns (uint256);

    function getRewardsAccrued(address _strategy) external view returns (uint256);

    function getExpectedShares(address _assetToken, uint256 _numTokensToSupply) external view returns (uint256);

    function getExchangeRatePerToken(address _assetToken) external view returns (uint256);

    function getInvestmentToken(address _assetToken) external view returns (address);

    function getInvestmentTokenAmount(address _address, address _assetToken) external view returns (uint256);
}
