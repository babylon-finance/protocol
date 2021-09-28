// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface ICurvePoolInt128 {
    function coins(int128 arg0) external view returns (address out);

    function underlying_coins(int128 arg0) external view returns (address out);

    function balances(int128 arg0) external view returns (uint256 out);

    function lp_token() external view returns (address out);

    function token() external view returns (address out);

    function curve() external view returns (address out);

    function pool() external view returns (address out);
}
