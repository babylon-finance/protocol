// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

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
