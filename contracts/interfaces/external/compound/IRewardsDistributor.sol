// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

interface IRewardsDistributor {
    function rewardToken() external view returns (address);

    function compAccrued(address _holder) external view returns (uint256);

    function claimRewards(address _holder) external;

    function compBorrowSpeeds(address _ctoken) external view returns (uint256);

    function compSupplySpeeds(address _ctoken) external view returns (uint256);
}
