// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

interface ISnxExchangeRates {
    function effectiveValue(
        bytes32 sourceCurrencyKey,
        uint256 sourceAmount,
        bytes32 destinationCurrencyKey
    ) external view returns (uint256 value);

    function rateForCurrency(bytes32 sourceCurrencyKey) external view returns (uint256 value);
}
