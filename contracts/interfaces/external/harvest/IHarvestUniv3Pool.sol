// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

interface IHarvestUniv3Pool {
    function deposit(
        uint256 _amount0,
        uint256 _amount1,
        bool _zapFunds,
        uint256 _sqrtRatioX96,
        uint256 _tolerance,
        uint256 _zapAmount0OutMin,
        uint256 _zapAmount1OutMin,
        uint160 _zapSqrtPriceLimitX96
    ) external;

    function withdraw(
        uint256 _numberOfShares,
        bool _token0,
        bool _token1,
        uint256 _sqrtRatioX96,
        uint256 _tolerance
    ) external;

    function approve(address spender, uint256 amount) external;

    function governance() external view returns (address);

    function controller() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getSqrtPriceX96() external view returns (uint160);

    function getStorage() external view returns (address);

    function getPricePerFullShare() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);
}
