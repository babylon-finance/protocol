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
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICommunity } from "../interfaces/ICommunity.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IBabController } from "../interfaces/IBabController.sol";
import { BaseIntegration } from "./BaseIntegration.sol";

/**
 * @title BorrowIntetration
 * @author Babylon Finance Protocol
 *
 * Base class for integration with trading protocols
 */
abstract contract TradeIntegration is BaseIntegration, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeCast for uint256;

    /* ============ Struct ============ */

    struct TradeInfo {
      ICommunity community;                                     // Community
      string exchangeName;                            // Which exchange to use
      address sendToken;                              // Address of token being sold
      address receiveToken;                           // Address of token being bought
      uint256 communityTotalSupply;                        // Total supply of Community in Precise Units (10^18)
      uint256 totalSendQuantity;                      // Total quantity of sold tokens
      uint256 totalMinReceiveQuantity;                // Total minimum quantity of token to receive back
      uint256 preTradeSendTokenBalance;               // Total initial balance of token being sold
      uint256 preTradeReceiveTokenBalance;            // Total initial balance of token being bought
    }


    /* ============ Events ============ */

    event ComponentExchanged(
      ICommunity indexed _community,
      address indexed _sendToken,
      address indexed _receiveToken,
      string _exchangeName,
      uint256 _totalSendAmount,
      uint256 _totalReceiveAmount,
      uint256 _protocolFee
    );


    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, address _weth, address _controller) BaseIntegration(_name, _weth, _controller) {
    }

    /* ============ External Functions ============ */

    /**
     * Executes a trade on a supported DEX. Only callable by the SetToken's manager.
     * @dev Although the SetToken units are passed in for the send and receive quantities, the total quantity
     * sent and received is the quantity of SetToken units multiplied by the SetToken totalSupply.
     *
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of token in SetToken sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     * @param _minReceiveQuantity   Min units of token in SetToken to be received from the exchange
     * @param _data                 Arbitrary bytes to be used to construct trade call data
     */
    function trade(
      address _sendToken,
      uint256 _sendQuantity,
      address _receiveToken,
      uint256 _minReceiveQuantity,
      bytes memory _data
    )
      external
      nonReentrant
      onlyCommunity
    {
      TradeInfo memory tradeInfo = _createTradeInfo(
        name,
        _sendToken,
        _receiveToken,
        _sendQuantity,
        _minReceiveQuantity
      );
      _validatePreTradeData(tradeInfo, _sendQuantity);
      _executeTrade(tradeInfo, _data);
      uint256 exchangedQuantity = _validatePostTrade(tradeInfo);
      uint256 protocolFee = _accrueProtocolFee(tradeInfo, exchangedQuantity);

      (
        uint256 netSendAmount,
        uint256 netReceiveAmount
      ) = _updateCommunityPositions(tradeInfo, exchangedQuantity);

      emit ComponentExchanged(
        tradeInfo.community,
        _sendToken,
        _receiveToken,
        tradeInfo.exchangeName,
        netSendAmount,
        netReceiveAmount,
        protocolFee
      );
    }

    /* ============ Internal Functions ============ */

    /**
     * Retrieve fee from controller and calculate total protocol fee and send from community to protocol recipient
     *
     * @param _tradeInfo                Struct containing trade information used in internal functions
     * @return uint256                  Amount of receive token taken as protocol fee
     */
    function _accrueProtocolFee(TradeInfo memory _tradeInfo, uint256 _exchangedQuantity) internal returns (uint256) {
      uint256 protocolFeeTotal = getIntegrationFee(0, _exchangedQuantity);

      payProtocolFeeFromCommunity(address(_tradeInfo.community), _tradeInfo.receiveToken, protocolFeeTotal);

      return protocolFeeTotal;
    }

    /**
     * Create and return TradeInfo struct
     *
     * @param _exchangeName         Human readable name of the exchange in the integrations registry
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     * @param _sendQuantity         Units of token in SetToken sent to the exchange
     * @param _minReceiveQuantity   Min units of token in SetToken to be received from the exchange
     *
     * return TradeInfo             Struct containing data for trade
     */
    function _createTradeInfo(
      string memory _exchangeName,
      address _sendToken,
      address _receiveToken,
      uint256 _sendQuantity,
      uint256 _minReceiveQuantity
    )
      internal
      view
      returns (TradeInfo memory)
    {
      TradeInfo memory tradeInfo;

      tradeInfo.community = ICommunity(msg.sender);

      tradeInfo.exchangeName = _exchangeName;

      tradeInfo.sendToken = _sendToken;
      tradeInfo.receiveToken = _receiveToken;

      tradeInfo.communityTotalSupply = tradeInfo.community.totalSupply();

      tradeInfo.totalSendQuantity = _sendQuantity;

      tradeInfo.totalMinReceiveQuantity = _minReceiveQuantity;

      tradeInfo.preTradeSendTokenBalance = IERC20(_sendToken).balanceOf(address(msg.sender));
      tradeInfo.preTradeReceiveTokenBalance = IERC20(_receiveToken).balanceOf(address(msg.sender));

      return tradeInfo;
    }

    /**
     * Validate pre trade data. Check exchange is valid, token quantity is valid.
     *
     * @param _tradeInfo            Struct containing trade information used in internal functions
     * @param _sendQuantity         Units of token in SetToken sent to the exchange
     */
    function _validatePreTradeData(TradeInfo memory _tradeInfo, uint256 _sendQuantity) internal view {
      require(_tradeInfo.totalSendQuantity > 0, "Token to sell must be nonzero");
      require(IBabController(controller).isValidAsset(_tradeInfo.receiveToken), "Receive token must be whitelisted");
      require(IERC20(_tradeInfo.sendToken).balanceOf(msg.sender) >= _sendQuantity, "Community needs to have enough liquid tokens");
      require(
          _tradeInfo.community.hasSufficientBalance(_tradeInfo.sendToken, _sendQuantity),
          "Position needs to have enough"
      );
    }

    /**
     * Invoke approve for community, get method data and invoke trade in the context of the community.
     *
     * @param _tradeInfo            Struct containing trade information used in internal functions
     * @param _data                 Arbitrary bytes to be used to construct trade call data
     */
    function _executeTrade(
      TradeInfo memory _tradeInfo,
      bytes memory _data
    )
      internal
    {
      // Get spender address from exchange adapter and invoke approve for exact amount on sendToken
      _tradeInfo.community.invokeApprove(
        _getSpender(),
        _tradeInfo.sendToken,
        _tradeInfo.totalSendQuantity
      );
      (
          address targetExchange,
          uint256 callValue,
          bytes memory methodData
      ) = _getTradeCalldata(
          _tradeInfo.sendToken,
          _tradeInfo.receiveToken,
          address(_tradeInfo.community),
          _tradeInfo.totalSendQuantity,
          _tradeInfo.totalMinReceiveQuantity,
          _data
      );
      _tradeInfo.community.invokeFromIntegration(targetExchange, callValue, methodData);
    }

    /**
     * Validate post trade data.
     *
     * @param _tradeInfo                Struct containing trade information used in internal functions
     * @return uint256                  Total quantity of receive token that was exchanged
     */
    function _validatePostTrade(TradeInfo memory _tradeInfo) internal view returns (uint256) {
      uint256 exchangedQuantity = IERC20(_tradeInfo.receiveToken)
        .balanceOf(address(_tradeInfo.community))
        .sub(_tradeInfo.preTradeReceiveTokenBalance);
      require(
        exchangedQuantity >= _tradeInfo.totalMinReceiveQuantity,
        "Slippage greater than allowed"
      );

      return exchangedQuantity;
    }

    /**
     * Update Community positions
     *
     * @param _tradeInfo                Struct containing trade information used in internal functions
     * @return uint256                  Amount of sendTokens used in the trade
     * @return uint256                  Amount of receiveTokens received in the trade (net of fees)
     */
    function _updateCommunityPositions(TradeInfo memory _tradeInfo, uint256 exchangedQuantity) internal returns (uint256, uint256) {
      uint256 newAmountSendTokens = _tradeInfo.preTradeSendTokenBalance.sub(_tradeInfo.totalSendQuantity);
      uint256 newAmountReceiveTokens = _tradeInfo.preTradeReceiveTokenBalance.add(exchangedQuantity);
      updateCommunityPosition(address(_tradeInfo.community), _tradeInfo.sendToken, int256(-_tradeInfo.totalSendQuantity), 0);
      updateCommunityPosition(address(_tradeInfo.community), _tradeInfo.receiveToken, exchangedQuantity.toInt256(), 0);

      return (newAmountSendTokens, newAmountReceiveTokens);
    }

    /**
     * Return exchange calldata which is already generated from the exchange API
     *
     * hparam  _sourceToken              Address of source token to be sold
     * hparam  _destinationToken         Address of destination token to buy
     * hparam  _sourceQuantity           Amount of source token to sell
     * hparam  _minDestinationQuantity   Min amount of destination token to buy
     * hparam  _data                    Arbitrage bytes containing trade call data
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getTradeCalldata(
      address /* _sourceToken */,
      address /* _destinationToken */,
      address /* _destinationAddress */,
      uint256 /* _sourceQuantity */,
      uint256 /* _minDestinationQuantity */,
      bytes memory /* _data */
    ) internal virtual view returns (address, uint256, bytes memory) {
      require(false, "This needs to be overriden");
      return (address(0),0,bytes(""));
    }

    /**
     * Returns the address to approve source tokens to for trading. This is the TokenTaker address
     *
     * @return address     Address of the contract to approve tokens to
     */
    function _getSpender() internal view virtual returns (address) {
      require(false, "This needs to be overriden");
      return address(0);
    }

}
