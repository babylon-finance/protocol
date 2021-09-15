// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IBasicRewards {
    function getReward(address _account, bool _claimExtras) external;

    function getReward(address _account) external;

    function stakeFor(address, uint256) external;

    function earned(address _account) external view returns (uint256);
}
