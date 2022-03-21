// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

interface IGammaDeposit {
    function deposit(
        uint256 _amount0,
        uint256 _amount1,
        address _to,
        address _visor
    ) external;
}
