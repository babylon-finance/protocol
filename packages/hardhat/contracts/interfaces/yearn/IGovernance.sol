// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

interface IGovernance {
    function withdraw(uint256) external;

    function getReward() external;

    function stake(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function exit() external;

    function voteFor(uint256) external;

    function voteAgainst(uint256) external;
}
