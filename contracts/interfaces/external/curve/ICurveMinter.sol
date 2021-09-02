// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface ICurveMinter {
    function mint(address gauge_addr) external;

    function minted(address _for, address gauge_addr) external view returns (uint256);

    function toggle_approve_mint(address minting_user) external;

    function token() external view returns (address);
}
