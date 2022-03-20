// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IMooniswap is IERC20 {
    function getTokens() external view returns (address[] memory _tokens);

    function tokens(uint256 i) external view returns (IERC20);

    function mooniswapFactoryGovernance() external view returns (address);

    function getBalanceForAddition(IERC20 token) external view returns (uint256);

    function getBalanceForRemoval(IERC20 token) external view returns (uint256);

    function getReturn(
        IERC20 src,
        IERC20 dst,
        uint256 amount
    ) external view returns (uint256);

    function deposit(uint256[2] memory maxAmounts, uint256[2] memory minAmounts)
        external
        payable
        returns (uint256 fairSupply, uint256[2] memory receivedAmounts);

    function depositFor(
        uint256[2] memory maxAmounts,
        uint256[2] memory minAmounts,
        address target
    ) external payable returns (uint256 fairSupply, uint256[2] memory receivedAmounts);

    function withdraw(uint256 amount, uint256[] memory minReturns)
        external
        returns (uint256[2] memory withdrawnAmounts);

    function withdrawFor(
        uint256 amount,
        uint256[] memory minReturns,
        address payable target
    ) external returns (uint256[2] memory withdrawnAmounts);

    function swap(
        IERC20 src,
        IERC20 dst,
        uint256 amount,
        uint256 minReturn,
        address referral
    ) external payable returns (uint256 result);

    function swapFor(
        IERC20 src,
        IERC20 dst,
        uint256 amount,
        uint256 minReturn,
        address referral,
        address payable receiver
    ) external payable returns (uint256 result);
}
