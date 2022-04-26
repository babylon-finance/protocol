// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

interface IPickleGauge {
    function earned(address _account) external view returns (uint256);

    function getReward() external;
}
