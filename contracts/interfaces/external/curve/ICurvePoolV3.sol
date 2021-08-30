interface ICurvePoolV3 {
    /*
    NCOINS is a private constant
    function add_liquidity(uint256[4] calldata amounts, uint256 deadline) external returns (uint256 out);

    function remove_liquidity(
        uint256 _amount,
        uint256 deadline,
        uint256[4] calldata min_amounts
    ) external external returns(uint256[4] amounts_returned);
    */

    function coins(uint256 arg0) external view returns (address out);

    function underlying_coins(uint256 arg0) external view returns (address out);

    function get_dy(int128 i, int128 j, uint256 amount) external view returns (uint256);

    function get_dy(uint256 i, uint256 j, uint256 amount) external view returns (uint256);

    function balances(uint256 arg0) external view returns (uint256 out);

    function lp_token() external view returns (address out);

    function token() external view returns (address out);

    function curve() external view returns (address out);

    function pool() external view returns (address out);
}
