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
import { TradeIntegration } from "./TradeIntegration.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { PreciseUnitMath } from "../lib/PreciseUnitMath.sol";
import { IKyberNetworkProxy } from "../interfaces/external/kyber/IKyberNetworkProxy.sol";

/**
 * @title KyberTradeIntegration
 * @author dFolio Protocol
 *
 * Kyber protocol trade integration
 */
contract KyberTradeIntegration is TradeIntegration {
  using SafeMath for uint256;
  using PreciseUnitMath for uint256;

  /* ============ Structs ============ */

  /**
   * Struct containing information for trade function
   */
  struct KyberTradeInfo {
    uint256 sourceTokenDecimals;        // Decimals of the token to send
    uint256 destinationTokenDecimals;   // Decimals of the token to receive
    uint256 conversionRate;             // Derived conversion rate from min receive quantity
  }

  /* ============ State Variables ============ */

  // Address of Kyber Network Proxy
  address public kyberNetworkProxyAddress;


  /* ============ Constructor ============ */

  /**
   * Creates the integration
   *
   * @param _name                         Name of the integration
   * @param _weth                         Address of the WETH ERC20
   * @param _controller                   Address of the controller
   * @param _kyberNetworkProxyAddress    Address of Kyber Network Proxy contract
   */
  constructor(
    string memory _name,
    address _weth,
    address _controller,
    address _kyberNetworkProxyAddress
  ) TradeIntegration(_name, _weth, _controller) {
    kyberNetworkProxyAddress = _kyberNetworkProxyAddress;
  }

  /* ============ External Functions ============ */

  /**
   * Returns the conversion rate between the source token and the destination token
   * in 18 decimals, regardless of component token's decimals
   *
   * @param  _sourceToken        Address of source token to be sold
   * @param  _destinationToken   Address of destination token to buy
   * @param  _sourceQuantity     Amount of source token to sell
   *
   * @return uint256             Conversion rate in wei
   * @return uint256             Slippage rate in wei
   */
  function getConversionRates(
    address _sourceToken,
    address _destinationToken,
    uint256 _sourceQuantity
  )
    external
    view
    returns (uint256, uint256)
  {
    // Get Kyber expectedRate to trade with
    return IKyberNetworkProxy(kyberNetworkProxyAddress).getExpectedRate(
      _sourceToken,
      _destinationToken,
      _sourceQuantity
    );
  }

  /* ============ Internal Functions ============ */

  /**
   * Calculate Kyber trade encoded calldata. To be invoked on the SetToken.
   *
   * @param  _sourceToken              Address of source token to be sold
   * @param  _destinationToken         Address of destination token to buy
   * @param  _destinationAddress       Address to receive traded tokens
   * @param  _sourceQuantity           Amount of source token to sell
   * @param  _minDestinationQuantity   Min amount of destination token to buy
   *
   * @return address                   Target address
   * @return uint256                   Call value
   * @return bytes                     Trade calldata
   */
  function _getTradeCalldata(
    address _sourceToken,
    address _destinationToken,
    address _destinationAddress,
    uint256 _sourceQuantity,
    uint256 _minDestinationQuantity,
    bytes memory /* _data */
  )
    internal
    override
    view
    returns (address, uint256, bytes memory)
  {
    KyberTradeInfo memory kyberTradeInfo;

    kyberTradeInfo.sourceTokenDecimals = ERC20(_sourceToken).decimals();
    kyberTradeInfo.destinationTokenDecimals = ERC20(_destinationToken).decimals();

    // Get conversion rate from minimum receive token quantity.
    // dstQty * (10 ** 18) * (10 ** dstDecimals) / (10 ** srcDecimals) / srcQty
    kyberTradeInfo.conversionRate = _minDestinationQuantity
      .mul(PreciseUnitMath.preciseUnit())
      .mul(10 ** kyberTradeInfo.sourceTokenDecimals)
      .div(10 ** kyberTradeInfo.destinationTokenDecimals)
      .div(_sourceQuantity);

    // Encode method data for SetToken to invoke
    bytes memory methodData = abi.encodeWithSignature(
      "trade(address,uint256,address,address,uint256,uint256,address)",
      _sourceToken,
      _sourceQuantity,
      _destinationToken,
      _destinationAddress,
      PreciseUnitMath.maxUint256(), // Sell entire amount of sourceToken
      kyberTradeInfo.conversionRate, // Trade with implied conversion rate
      address(0) // No referrer address
    );

    return (kyberNetworkProxyAddress, 0, methodData);
  }

  /**
   * Returns the address to approve source tokens to for trading. This is the Kyber Network
   * Proxy address
   *
   * @return address             Address of the contract to approve tokens to
   */
  function _getSpender()
    internal
    override
    view
    returns (address)
  {
    return kyberNetworkProxyAddress;
  }

}
