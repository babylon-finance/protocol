// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {TradesIterator} from '../interfaces/IOperation.sol';
import {IStrategy, TradeInfo, TradeProtocol} from '../interfaces/IStrategy.sol';

library TradeIteratorLib {
    function next(TradesIterator memory _iter) internal returns (TradeInfo memory) {
        return _iter.trades.length > (_iter.counter) ? _iter.trades[_iter.counter++] : TradeIteratorLib.none();
    }

    function none() internal returns (TradeInfo memory) {
        return TradeInfo(new TradeProtocol[](0), new address[](0), new address[](0));
    }
}
