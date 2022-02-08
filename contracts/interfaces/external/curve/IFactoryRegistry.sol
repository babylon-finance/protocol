// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IFactoryRegistry {
    function find_pool_for_coins(
        address _from,
        address _to,
        uint256 _i
    ) external view returns (address);

    function find_pool_for_coins(address _from, address _to) external view returns (address);

    function get_n_coins(address _pool) external view returns (uint256[2] memory);

    function get_rates(address _pool) external view returns (uint256[2] memory);

    function pool_count() external view returns (uint256);

    function pool_list(uint256 i) external view returns (address);

    function get_A(address _pool) external view returns (uint256);

    function get_coins(address _pool) external view returns (address[2] memory);

    function get_underlying_coins(address _pool) external view returns (address[8] memory);

    function get_coin_indices(
        address _pool,
        address _from,
        address _to
    )
        external
        view
        returns (
            int128,
            int128,
            bool
        );
}
