// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

interface ICToken {
    function mint(uint256 mintAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function repayBorrow(uint256 repayAmount) external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function balanceOf(address _owner) external view returns (uint256);

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

    function exchangeRateCurrent() external returns (uint256);

    function supplyRatePerBlock() external returns (uint256);
}
