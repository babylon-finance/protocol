pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStETH is IERC20 {
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);

    function getSharesByPooledEth(uint256 _pooledEthAmount) external view returns (uint256);

    function submit(address _referral) external payable returns (uint256);
}
