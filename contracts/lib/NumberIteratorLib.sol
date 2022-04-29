// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {NumbersIterator} from '../interfaces/IOperation.sol';

library NumberIteratorLib {
    function next(NumbersIterator memory _iter) internal returns (uint256) {
        return _iter.items.length > (_iter.counter) ? _iter.items[_iter.counter++] : 0;
    }
}
