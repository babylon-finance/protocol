// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IStrategy} from '../interfaces/IStrategy.sol';

/**
 * @title IntegerUtils
 */
library IntegerUtils {

    function toDynamic(uint256 _one) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = _one;
        return arr;
    }

    function toDynamic(IStrategy.TradeProtocol _one) internal pure returns (IStrategy.TradeProtocol[] memory) {
        IStrategy.TradeProtocol[] memory arr = new IStrategy.TradeProtocol[](1);
        arr[0] = _one;
        return arr;
    }

    function toDynamic(IStrategy.TradeProtocol _one, IStrategy.TradeProtocol _two) internal pure returns (IStrategy.TradeProtocol[] memory) {
        IStrategy.TradeProtocol[] memory arr = new IStrategy.TradeProtocol[](2);
        arr[0] = _one;
        arr[1] = _two;
        return arr;
    }
}
