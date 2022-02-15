// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface ICurvePoolV3DY {
    function get_dy(
        uint256 i,
        uint256 j,
        uint256 amount
    ) external view returns (uint256);

    function get_dy_underlying(
        uint256 i,
        uint256 j,
        uint256 amount
    ) external view returns (uint256);
}
