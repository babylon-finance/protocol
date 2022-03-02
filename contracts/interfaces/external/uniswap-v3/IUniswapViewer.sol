// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.9;

interface IUniswapViewer {
    function getAmountsForPosition(uint256 posId) external view returns (uint256, uint256);
}
