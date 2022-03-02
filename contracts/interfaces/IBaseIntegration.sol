// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.9;
pragma abicoder v1;

interface IBaseIntegration {
    function name() external view returns (string memory);
}
