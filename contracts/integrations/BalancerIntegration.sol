/*
    Copyright 2020 Babylon Finance

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
import { IBFactory } from "../interfaces/external/balancer/IBFactory.sol";

/**
 * @title BalancerIntegration
 * @author Babylon Finance Protocol
 *
 * Kyber protocol trade integration
 */
contract BalancerIntegration is PoolIntegration {
  using SafeMath for uint256;
  using PreciseUnitMath for uint256;

  /* ============ State Variables ============ */

  // Address of Kyber Network Proxy
  IBFactory public coreFactory;


  /* ============ Constructor ============ */

  /**
   * Creates the integration
   *
   * @param _controller                   Address of the controller
   * @param _weth                         Address of the WETH ERC20
   * @param _coreFactoryAddress           Address of Balancer core factory address
   */
  constructor(
    address _controller,
    address _weth,
    address _coreFactoryAddress
  ) PoolIntegration("balancer", _weth, _controller) {
    coreFactory = IBFactory(_coreFactoryAddress);
  }


  /* ============ Internal Functions ============ */

  function _isPool(address _poolAddress) view override internal returns (bool) {
    return coreFactory.isBPool(_poolAddress);
  }

  function _getSpender(address _poolAddress) pure override internal returns (address) {
    return _poolAddress;
  }

  /**
   * Return join pool calldata which is already generated from the pool API
   *
   * @param  _poolAddress              Address of the pool
   * @param  _poolTokensOut            Amount of pool tokens to send
   * hparam  _tokensIn                 Addresses of tokens to send to the pool
   * @param  _maxAmountsIn             Amounts of tokens to send to the pool
   *
   * @return address                   Target contract address
   * @return uint256                   Call value
   * @return bytes                     Trade calldata
   */
  function _getJoinPoolCalldata(
    address _poolAddress,
    uint256 _poolTokensOut,
    address[] calldata /* _tokensIn */,
    uint256[] calldata _maxAmountsIn
  ) internal override pure returns (address, uint256, bytes memory) {
    // Encode method data for Fund to invoke
    bytes memory methodData = abi.encodeWithSignature(
      "joinPool(uint256,uint256[])",
      _poolTokensOut,
      _maxAmountsIn
    );

    return (_poolAddress, 0, methodData);
  }

  /**
   * Return exit pool calldata which is already generated from the pool API
   *
   * @param  _poolAddress              Address of the pool
   * @param  _poolTokensIn             Amount of pool tokens to receive
   * hparam  _tokensOut                Addresses of tokens to receive
   * @param  _minAmountsOut            Amounts of pool tokens to receive
   *
   * @return address                   Target contract address
   * @return uint256                   Call value
   * @return bytes                     Trade calldata
   */
  function _getExitPoolCalldata(
    address _poolAddress,
    uint256 _poolTokensIn,
    address[] calldata /* _tokensOut */,
    uint256[] calldata _minAmountsOut
  ) internal override pure returns (address, uint256, bytes memory) {
    // Encode method data for Fund to invoke
    bytes memory methodData = abi.encodeWithSignature(
      "exitPool(uint256,uint256[])",
      _poolTokensIn,
      _minAmountsOut
    );

    return (_poolAddress, 0, methodData);
  }
}
