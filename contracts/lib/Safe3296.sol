/*
    Copyright 2021 Babylon Finance.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.8.9;

import {LowGasSafeMath} from '../lib/LowGasSafeMath.sol';

library Safe3296 {
    using LowGasSafeMath for uint256;

    /**
     * INTERNAL FUNCTION. Internal function to convert from uint256 to uint32
     *
     * @dev internal function to convert from uint256 to uint32
     */
    function safe32(uint256 n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    /**
     * INTERNAL FUNCTION. Internal function to convert from uint256 to uint96
     *
     * @dev internal function to convert from uint256 to uint96
     */
    function safe96(uint256 n, string memory errorMessage) internal pure returns (uint96) {
        require(n < 2**96, errorMessage);
        return uint96(n);
    }

    /**
     * INTERNAL FUNCTION. Internal function to add two uint96 numbers
     *
     * @dev internal safe math function to add two uint96 numbers
     */
    function add96(
        uint96 a,
        uint96 b,
        string memory errorMessage
    ) internal pure returns (uint96) {
        uint96 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    /**
     * INTERNAL FUNCTION. Internal function to subtract two uint96 numbers
     *
     * @dev internal safe math function to subtract two uint96 numbers
     */
    function sub96(
        uint96 a,
        uint96 b,
        string memory errorMessage
    ) internal pure returns (uint96) {
        require(b <= a, errorMessage);
        return a - b;
    }
}
