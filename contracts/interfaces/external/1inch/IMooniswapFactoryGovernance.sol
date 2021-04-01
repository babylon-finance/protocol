// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

interface IMooniswapFactoryGovernance {
    function shareParameters()
        external
        view
        returns (
            uint256 _referralShare,
            uint256 _governanceShare,
            address _governanceWallet,
            address _referralFeeReceiver
        );

    function defaults()
        external
        view
        returns (
            uint256 _defaultFee,
            uint256 _defaultSlippageFee,
            uint256 _defaultDecayPeriod
        );

    function defaultFee() external view returns (uint256);

    function defaultSlippageFee() external view returns (uint256);

    function defaultDecayPeriod() external view returns (uint256);

    function virtualDefaultFee()
        external
        view
        returns (
            uint104,
            uint104,
            uint48
        );

    function virtualDefaultSlippageFee()
        external
        view
        returns (
            uint104,
            uint104,
            uint48
        );

    function virtualDefaultDecayPeriod()
        external
        view
        returns (
            uint104,
            uint104,
            uint48
        );

    function referralShare() external view returns (uint256);

    function governanceShare() external view returns (uint256);

    function governanceWallet() external view returns (address);

    function feeCollector() external view returns (address);

    function isFeeCollector(address) external view returns (bool);

    function isActive() external view returns (bool);
}
