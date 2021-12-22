// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

interface IHarvestV3Stake {
    function earned(uint256 i, address account) external view returns (uint256);

    function rewardTokensLength() external view returns (uint256);

    function lpToken() external view returns (address);

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getAllRewards() external;

    function rewardTokens(uint256 i) external view returns (address);
}
