// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

/**
 * @title ICustomIntegration
 * @author Babylon Finance
 *
 * Interface for custom protocol integrations
 */
interface ICustomIntegration {
    function enter(
        address _strategy,
        bytes calldata _data,
        uint256 _resultTokensOut,
        address[] memory _inputTokens,
        uint256[] memory _maxAmountsIn
    ) external;

    function exit(
        address _strategy,
        bytes calldata _data,
        uint256 _resultTokensIn,
        address[] memory _inputTokens,
        uint256[] memory _minAmountsOut
    ) external;

    function isValid(bytes calldata _data) external view returns (bool);

    function getInputTokensAndWeights(bytes calldata _data) external view returns (address[] memory, uint256[] memory);

    function getResultToken(address _data) external view returns (address);

    function getPriceResultToken(bytes calldata _data, address _tokenAddress) external view returns (uint256);

    function getOutputTokensAndMinAmountOut(bytes calldata _data, uint256 _resultTokenAmount)
        external
        view
        returns (address[] memory exitTokens, uint256[] memory _minAmountsOut);

    function getRewardTokens(bytes calldata _data) external view returns (address[] memory);
}
