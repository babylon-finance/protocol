// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

interface IYearnVault {
    function pricePerShare() external view returns (uint256);

    function name() external view returns (string memory);

    function token() external view returns (address);

    function deposit(uint256 amount) external;

    function withdraw(uint256 shares) external;

    function balanceOf(address) external view returns (uint256);
}
