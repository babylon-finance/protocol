// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

interface IYearnRegistry {
    function latestVault(address asset) external view returns (address);
}
