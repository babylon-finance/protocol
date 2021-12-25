// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

// See https://mobile.twitter.com/curvefinance/status/1441538795493478415
// https://etherscan.io/address/0xE8b2989276E2Ca8FDEA2268E3551b2b4B2418950#readContract
interface IPriceTri {
    function lp_price() external view returns (uint256);
}
