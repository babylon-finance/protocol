// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import {ICToken} from '../compound/ICToken.sol';

interface ICreamPriceOracleProxy {
    function getUnderlyingPrice(ICToken cToken) external view returns (uint256);
}
