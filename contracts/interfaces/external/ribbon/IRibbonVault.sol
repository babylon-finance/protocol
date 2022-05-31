// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma abicoder v2;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IRibbonVault is IERC20 {
    struct VaultParams {
        // Option type the vault is selling
        bool isPut;
        // Token decimals for vault shares
        uint8 decimals;
        // Asset used in Theta / Delta Vault
        address asset;
        // Underlying asset of the options sold by vault
        address underlying;
        // Minimum supply of the vault shares issued, for ETH it's 10**10
        uint56 minimumSupply;
        // Vault cap
        uint104 cap;
    }

    function depositETH() external payable;

    function deposit(uint256 amount) external;

    function depositFor(uint256 amount, address creditor) external;

    function redeem(uint256 numShares) external;

    function maxRedeem() external;

    function initiateWithdraw(uint256 numShares) external;

    function completeWithdraw() external;

    function pricePerShare() external view returns (uint256);

    function cap() external view returns (uint256);

    function shares(address account) external view returns (uint256);

    function liquidityGauge() external view returns (address);

    function vaultParams() external view returns (VaultParams memory);
}
