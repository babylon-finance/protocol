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
import { PassiveIntegration } from "./PassiveIntegration.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { PreciseUnitMath } from "../lib/PreciseUnitMath.sol";
import { YRegistry } from "../interfaces/external/yearn/YRegistry.sol";

/**
 * @title YearnIntegration
 * @author dFolio Protocol
 *
 * Yearn v2 Vault Integration
 */
contract YearnVaultIntegration is PassiveIntegration {
  using SafeMath for uint256;
  using PreciseUnitMath for uint256;

  /* ============ State Variables ============ */

  // Address of Kyber Network Proxy
  YRegistry public yearnv2Registry;


  /* ============ Constructor ============ */

  /**
   * Creates the integration
   *
   * @param _controller                   Address of the controller
   * @param _weth                         Address of the WETH ERC20
   * @param _yearnRegistryAddress           Address of Balancer core factory address
   */
  constructor(
    address _controller,
    address _weth,
    address _yearnRegistryAddress
  ) PassiveIntegration("yearnvaults", _weth, _controller) {
    yearnv2Registry = YRegistry(_yearnRegistryAddress);
  }


  /* ============ Internal Functions ============ */

  function _isInvestment(address _investmentAddress) view override internal returns (bool) {
    (address _controller,,,,) = yearnv2Registry.getVaultInfo(_investmentAddress);
    return _controller != address(0);
  }

  function _getSpender(address _investmentAddress) pure override internal returns (address) {
    return _investmentAddress;
  }

  /**
   * Return join investment calldata which is already generated from the investment API
   *
   * @param  _investmentAddress              Address of the vault
   * @param  _investmentTokensOut            Amount of investment tokens to send
   * @param  _tokenIn                        Addresses of tokens to send to the investment
   * @param  _maxAmountIn                    Amounts of tokens to send to the investment
   *
   * @return address                         Target contract address
   * @return uint256                         Call value
   * @return bytes                           Trade calldata
   */
  function _getEnterInvestmentCalldata(
    address _investmentAddress,
    uint256 _investmentTokensOut,
    address _tokenIn,
    uint256 _maxAmountIn
  ) internal override pure returns (address, uint256, bytes memory) {
    // Encode method data for Fund to invoke
    bytes memory methodData = abi.encodeWithSignature(
      "deposit(uint256)",
      _maxAmountIn
    );

    return (_investmentAddress, 0, methodData);
  }

  /**
   * Return exit investment calldata which is already generated from the investment API
   *
   * @param  _investmentAddress              Address of the investment
   * @param  _investmentTokensIn             Amount of investment tokens to receive
   * @param  _tokenOut                       Addresses of tokens to receive
   * @param  _minAmountOut                   Amounts of investment tokens to receive
   *
   * @return address                         Target contract address
   * @return uint256                         Call value
   * @return bytes                           Trade calldata
   */
  function _getExitInvestmentCalldata(
    address _investmentAddress,
    uint256 _investmentTokensIn,
    address _tokenOut,
    uint256 _minAmountOut
  ) internal override pure returns (address, uint256, bytes memory) {
    // Encode method data for Fund to invoke
    bytes memory methodData = abi.encodeWithSignature(
      "withdraw(uint256)",
      _investmentTokensIn
    );

    return (_investmentAddress, 0, methodData);
  }
}
