// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface ICurvePoolV3 {
    function coins(uint256 arg0) external view returns (address out);

    function underlying_coins(uint256 arg0) external view returns (address out);

    function underlying_coins(int128 arg0) external view returns (address out);

    function get_dy(
        int128 i,
        int128 j,
        uint256 amount
    ) external view returns (uint256);

    function get_dy_underlying(
        int128 i,
        int128 j,
        uint256 amount
    ) external view returns (uint256);

    function balances(uint256 arg0) external view returns (uint256 out);

    function get_virtual_price() external view returns (uint256);

    function lp_price() external view returns (uint256);

    function lp_token() external view returns (address out);

    function token() external view returns (address out);

    function curve() external view returns (address out);

    function pool() external view returns (address out);
}
