// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

interface ICompoundPriceOracle {
    function getUnderlyingPrice(address cToken) external view returns (uint256);
}
