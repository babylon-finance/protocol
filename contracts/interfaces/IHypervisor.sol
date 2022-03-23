// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.7.6;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IHypervisor {
    // @param deposit0 Amount of token0 transfered from sender to Hypervisor
    // @param deposit1 Amount of token0 transfered from sender to Hypervisor
    // @param to Address to which liquidity tokens are minted
    // @return shares Quantity of liquidity tokens minted as a result of deposit
    function deposit(
        uint256 deposit0,
        uint256 deposit1,
        address to
    ) external returns (uint256);

    // @param shares Number of liquidity tokens to redeem as pool assets
    // @param to Address to which redeemed pool assets are sent
    // @param from Address from which liquidity tokens are sent
    // @return amount0 Amount of token0 redeemed by the submitted liquidity tokens
    // @return amount1 Amount of token1 redeemed by the submitted liquidity tokens
    function withdraw(
        uint256 shares,
        address to,
        address from
    ) external returns (uint256, uint256);

    function rebalance(
        int24 _baseLower,
        int24 _baseUpper,
        int24 _limitLower,
        int24 _limitUpper,
        address _feeRecipient,
        int256 swapQuantity
    ) external;

    function addBaseLiquidity(uint256 amount0, uint256 amount1) external;

    function addLimitLiquidity(uint256 amount0, uint256 amount1) external;

    function pullLiquidity(uint256 shares)
        external
        returns (
            uint256 base0,
            uint256 base1,
            uint256 limit0,
            uint256 limit1
        );

    function token0() external view returns (IERC20);

    function token1() external view returns (IERC20);

    function pool() external view returns (address);

    function balanceOf(address) external view returns (uint256);

    function approve(address, uint256) external returns (bool);

    function transferFrom(
        address,
        address,
        uint256
    ) external returns (bool);

    function transfer(address, uint256) external returns (bool);

    function getTotalAmounts() external view returns (uint256 total0, uint256 total1);

    function pendingFees() external returns (uint256 fees0, uint256 fees1);

    function totalSupply() external view returns (uint256);

    function setMaxTotalSupply(uint256 _maxTotalSupply) external;

    function setDepositMax(uint256 _deposit0Max, uint256 _deposit1Max) external;

    function appendList(address[] memory listed) external;

    function toggleWhitelist() external;

    function transferOwnership(address newOwner) external;
}
