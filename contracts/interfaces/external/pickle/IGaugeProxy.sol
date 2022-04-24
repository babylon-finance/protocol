// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

interface IGaugeProxy {
    function gauges(address _jar) external view returns (address);
}
