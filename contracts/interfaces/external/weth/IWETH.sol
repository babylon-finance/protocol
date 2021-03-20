// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

interface IWETH {
    function deposit() external payable;

    function balanceOf(address _address) external view returns (uint256);

    function transfer(address dst, uint256 wad) external returns (bool);

    function withdraw(uint256 wad) external;

    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);
}
