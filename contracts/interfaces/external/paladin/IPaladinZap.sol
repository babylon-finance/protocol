// SPDX-License-Identifier: agpl-3.0

pragma solidity ^0.8.5;
pragma abicoder v1;

interface IPaladinZap {
    function zapDeposit(
        address _fromTokenAddress,
        address _toTokenAddress,
        address _poolAddress,
        uint256 _amount,
        address _swapTarget,
        address _allowanceTarget,
        bytes memory _swapData
    ) external payable returns (uint256);
}
