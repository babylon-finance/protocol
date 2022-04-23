// SPDX-License-Identifier: agpl-3.0

pragma solidity >=0.7.0 <0.9.0;

interface AaveToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
