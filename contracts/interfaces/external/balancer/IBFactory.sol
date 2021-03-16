// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import {IBPool} from './IBPool.sol';

interface IBFactory {
    function isBPool(address b) external view returns (bool);

    function newBPool() external returns (IBPool);
}
