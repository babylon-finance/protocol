// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

interface IRewardsDistributor {

  function rewardToken() external view returns (address);

  function compAccrued() external view returns (uint256);

  function claimRewards(address _holder) external;
}
