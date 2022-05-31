// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IGaugeController {
    function gauge_types(address _gauge) external view returns (int128);
}
