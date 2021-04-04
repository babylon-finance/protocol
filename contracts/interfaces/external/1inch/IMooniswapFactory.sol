// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './IMooniswap.sol';
import './IMooniswapFactoryGovernance.sol';

interface IMooniswapFactory is IMooniswapFactoryGovernance {
    function pools(IERC20 token0, IERC20 token1) external view returns (IMooniswap);

    function isPool(IMooniswap mooniswap) external view returns (bool);
}
