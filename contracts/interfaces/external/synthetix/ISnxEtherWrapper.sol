// SPDX-License-Identifier: MIT

pragma solidity >=0.4.24;

// https://docs.synthetix.io/contracts/source/interfaces/idepot
interface ISnxEtherWrapper {
    // Mints sEth. WETH -> sETH. Needs approval
    function mint(uint256 _amount) external;

    // Burns sETH. sETH -> WETH
    function burn(uint256 _amount) external;

    function capacity() external view returns (uint256);
}
