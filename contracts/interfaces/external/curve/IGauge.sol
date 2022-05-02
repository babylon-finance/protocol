// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IGauge {
    function claim_rewards(address _add, address _receiver) external;

    function deposit(address _add, uint256 _amount) external;

    function withdraw(uint256 _value) external;

    function rewarded_tokens(uint256 _id) external view returns (address);

    function balanceOf(address _addr) external view returns (uint256);

    function last_claim() external view returns (uint256);

    function claimed_reward(address _addr, address _token) external view returns (uint256);

    function claimable_reward(address _addr, address _token) external view returns (uint256);

    function claimable_reward_write(address _addr, address _token) external view returns (uint256);
}
