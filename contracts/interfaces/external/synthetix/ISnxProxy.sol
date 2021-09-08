// SPDX-License-Identifier: MIT

pragma solidity >=0.4.24;

// https://docs.synthetix.io/contracts/source/interfaces/isynth
interface ISnxProxy {
    // Views
    function target() external view returns (address);
}
