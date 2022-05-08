// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IFactoryRegistry {
    function get_pool_from_lp_token(address _lpToken) external view returns (address);

    function get_lp_token(address _pool) external view returns (address);

    function get_gauge(address _pool) external view returns (address);

    function find_pool_for_coins(
        address _from,
        address _to,
        uint256 _i
    ) external view returns (address);

    function find_pool_for_coins(address _from, address _to) external view returns (address);

    function get_n_coins(address _pool) external view returns (uint256);

    function get_meta_n_coins(address _pool) external view returns (uint256, uint256);

    function get_rates(address _pool) external view returns (uint256[8] memory);

    function get_virtual_price_from_lp_token(address _lpToken) external view returns (uint256);

    function is_meta(address _pool) external view returns (bool);

    function pool_count() external view returns (uint256);

    function pool_list(uint256 i) external view returns (address);

    function get_pool_name(address _pool) external view returns (string memory);

    function get_A(address _pool) external view returns (uint256);

    function get_coins(address _pool) external view returns (address[4] memory);

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
