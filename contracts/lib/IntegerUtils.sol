// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IStrategy, TradeProtocol} from '../interfaces/IStrategy.sol';

/**
 * @title IntegerUtils
 */
library IntegerUtils {

    function toDynamic(uint256 _one) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = _one;
        return arr;
    }

    function toDynamic(TradeProtocol _one) internal pure returns (TradeProtocol[] memory) {
        TradeProtocol[] memory arr = new TradeProtocol[](1);
        arr[0] = _one;
        return arr;
    }

    function toDynamic(TradeProtocol _one, TradeProtocol _two) internal pure returns (TradeProtocol[] memory) {
        TradeProtocol[] memory arr = new TradeProtocol[](2);
        arr[0] = _one;
        arr[1] = _two;
        return arr;
    }
}
