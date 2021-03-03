// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

interface IBRegistry {

    function getPairInfo(
      address pool,
      address fromToken,
      address destToken
    ) external view returns(uint256 weight1, uint256 weight2, uint256 swapFee);

    function getPoolsWithLimit(
      address fromToken,
      address destToken,
      uint256 offset,
      uint256 limit
    ) external view returns(address[] memory result);

    function getBestPools(
      address fromToken,
      address destToken
    ) external view returns(address[] memory pools);

    function getBestPoolsWithLimit(
      address fromToken,
      address destToken,
      uint256 limit
    ) external view returns(address[] memory pools);

    function addPoolPair(
      address pool,
      address token1,
      address token2
    ) external returns(uint256 listed);

    function addPools(
      address[] calldata pools,
      address token1,
      address token2
    ) external returns(uint256[] memory listed);

    function sortPools(address[] calldata tokens, uint256 lengthLimit) external;
    function sortPoolsWithPurge(address[] calldata tokens, uint256 lengthLimit) external;
}
