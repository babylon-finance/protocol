// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import './IJar.sol';

interface IJarUniV3 is IJar {
    function pool() external view returns (address);

    function getProportion() external view returns (uint256);

    function totalLiquidity() external view returns (uint256);

    function getAmountsForLiquidity(uint128 liquidity) external view returns (uint256, uint256);

    function token0() external view returns (address);

    function token1() external view returns (address);
}
