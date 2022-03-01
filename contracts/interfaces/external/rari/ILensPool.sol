// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;
pragma abicoder v2;

interface ILensPool {
    function getUnclaimedRewardsByDistributors(address _account, address[] memory _rds)
        external
        view
        returns (
            address[] memory,
            uint256[] memory,
            address[][] memory,
            uint256[2][][] memory,
            uint256[] memory
        );
}
