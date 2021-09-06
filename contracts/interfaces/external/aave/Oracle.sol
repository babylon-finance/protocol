// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.7.0 <0.9.0;

interface Oracle {
    function getAssetPrice(address reserve) external view returns (uint256);

    function latestAnswer() external view returns (uint256);
}
