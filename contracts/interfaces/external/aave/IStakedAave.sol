// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.5;
pragma abicoder v1;

interface IStakedAave {
    function stake(address to, uint256 amount) external;

    function redeem(address to, uint256 amount) external;

    function cooldown() external;

    function claimRewards(address to, uint256 amount) external;

    function stakerRewardsToClaim(address input) external view returns (uint256);
}
