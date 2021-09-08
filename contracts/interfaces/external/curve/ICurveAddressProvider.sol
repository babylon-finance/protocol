// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface ICurveAddressProvider {
    function get_registry() external view returns (address);

    function get_address(uint256 _id) external view returns (address);

    function max_id() external view returns (uint256);

    function get_id_info(uint256 _id)
        external
        view
        returns (
            address,
            bool,
            uint256,
            uint256,
            string calldata
        );
}
