// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface ICToken is IERC20 {
    function mint(uint256 mintAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function accrueInterest() external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function repayBorrow(uint256 repayAmount) external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function getCash() external view returns (uint256);

    function borrowRatePerBlock() external view returns (uint256);

    function totalBorrows() external view returns (uint256);

    function underlying() external view returns (address);

    function getAccountSnapshot(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        );

    function repayBorrowBehalf(address borrower, uint256 amount) external payable returns (uint256);

    function borrowBalanceCurrent(address account) external view returns (uint256);

    function supplyRatePerBlock() external returns (uint256);
}
