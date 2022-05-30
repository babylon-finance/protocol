// SPDX-License-Identifier: Apache-2.0

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

    function signalUnlock(address _strategy, bytes calldata _data) external;

    function getInvestmentAsset(address _investmentAddress) external view returns (address);

    function getResultAsset(address _investmentAddress) external view returns (address);

    function getResultBalance(address _strategy, address _resultAssetAddress) external view returns (uint256);

    function getRewards(address _strategy, address _investmentAddress) external view returns (address, uint256);

    function needsUnlockSignal(address _strategy, bytes calldata _data) external view returns (bool);
}
