// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

interface IPickleController {
    function strategies(address _pool) external view returns (address);
}
