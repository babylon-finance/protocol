/*
    Copyright 2020 DFolio

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.7.4;

import "hardhat/console.sol";
import { PoolIntegration } from "./PoolIntegration.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { PreciseUnitMath } from "../lib/PreciseUnitMath.sol";
import { IUniswapV2Router } from "../interfaces/external/uniswap/IUniswapV2Router.sol";
import { IUniswapV2Pair } from "../interfaces/external/uniswap/IUniswapV2Pair.sol";

/**
 * @title BalancerIntegration
 * @author dFolio Protocol
 *
 * Kyber protocol trade integration
 */
contract UniswapPoolIntegration is PoolIntegration {
  using SafeMath for uint256;
  using PreciseUnitMath for uint256;

  /* ============ State Variables ============ */

  // Address of Uniswap V2 Router
  IUniswapV2Router public uniRouter;
  uint8 immutable MAX_DELTA_BLOCKS = 5;


  /* ============ Constructor ============ */

  /**
   * Creates the integration
   *
   * @param _controller                   Address of the controller
   * @param _weth                         Address of the WETH ERC20
   * @param _uniswapRouterAddress         Address of Uniswap router
   */
  constructor(
    address _controller,
    address _weth,
    address _uniswapRouterAddress
  ) PoolIntegration("uniswap_pool", _weth, _controller) {
    uniRouter = IUniswapV2Router(_uniswapRouterAddress);
  }

  /* ============ Internal Functions ============ */

  function _isPool(address _poolAddress) view override internal returns (bool) {
    return IUniswapV2Pair(_poolAddress).MINIMUM_LIQUIDITY() > 0;
  }

  function _getSpender(address _poolAddress) view override internal returns (address) {
    return address(uniRouter);
  }

  /**
   * Return join pool calldata which is already generated from the pool API
   *
   * @param  _poolAddress              Address of the pool
   * @param  _poolTokensOut            Amount of pool tokens to send
   * @param  _tokensIn                 Addresses of tokens to send to the pool
   * @param  _maxAmountsIn             Amounts of tokens to send to the pool
   *
   * @return address                   Target contract address
   * @return uint256                   Call value
   * @return bytes                     Trade calldata
   */
  function _getJoinPoolCalldata(
    address _poolAddress,
    uint256 _poolTokensOut,
    address[] calldata _tokensIn,
    uint256[] calldata _maxAmountsIn
  ) internal override view returns (address, uint256, bytes memory) {
    // Encode method data for Fund to invoke
    require(_tokensIn.length == 2, "Adding liquidity to a uniswap pool requires exactly two tokens");
    require(_maxAmountsIn.length == 2, "Adding liquidity to a uniswap pool requires exactly two tokens");
    bytes memory methodData = abi.encodeWithSignature(
      "addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)",
      _tokensIn[0],
      _tokensIn[1],
      _maxAmountsIn[0],
      _maxAmountsIn[1],
      _maxAmountsIn[0] - 10000000,
      0, // TODO: tighten this up
      msg.sender,
      block.timestamp.add(MAX_DELTA_BLOCKS)
    );

    return (address(uniRouter), 0, methodData);
  }

  /**
   * Return exit pool calldata which is already generated from the pool API
   *
   * @param  _poolAddress              Address of the pool
   * @param  _poolTokensIn             Amount of pool tokens to receive
   * @param  _tokensOut                Addresses of tokens to receive
   * @param  _minAmountsOut            Amounts of pool tokens to receive
   *
   * @return address                   Target contract address
   * @return uint256                   Call value
   * @return bytes                     Trade calldata
   */
  function _getExitPoolCalldata(
    address _poolAddress,
    uint256 _poolTokensIn,
    address[] calldata _tokensOut,
    uint256[] calldata _minAmountsOut
  ) internal override view returns (address, uint256, bytes memory) {
    require(_tokensOut.length == 2, "Removing liquidity from a uniswap pool requires exactly two tokens");
    require(_minAmountsOut.length == 2, "Removing liquidity from a uniswap pool requires exactly two tokens");
    // Encode method data for Fund to invoke
    bytes memory methodData = abi.encodeWithSignature(
      "removeLiquidity(address,address,uint256,uint256,uint256,address,uint256)",
      _tokensOut[0],
      _tokensOut[1],
      _poolTokensIn,
      _minAmountsOut[0],
      _minAmountsOut[1],
      msg.sender,
      block.timestamp.add(MAX_DELTA_BLOCKS)
    );

    return (address(uniRouter), 0, methodData);
  }
}
