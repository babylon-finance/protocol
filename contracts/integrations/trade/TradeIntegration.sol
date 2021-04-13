/*
    Copyright 2021 Babylon Finance

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

import 'hardhat/console.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {BaseIntegration} from '../BaseIntegration.sol';

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
        IGarden garden; // Garden
        IStrategy strategy; // Idea
        string exchangeName; // Which exchange to use
        address sendToken; // Address of token being sold
        address receiveToken; // Address of token being bought
        uint256 gardenTotalSupply; // Total supply of Garden in Precise Units (10^18)
        uint256 totalSendQuantity; // Total quantity of sold tokens
        uint256 totalMinReceiveQuantity; // Total minimum quantity of token to receive back
        uint256 preTradeSendTokenBalance; // Total initial balance of token being sold
        uint256 preTradeReceiveTokenBalance; // Total initial balance of token being bought
    }

    /* ============ Events ============ */

    event ComponentExchanged(
        IGarden indexed _garden,
        IStrategy indexed _strategy,
        address indexed _sendToken,
        address _receiveToken,
        string _exchangeName,
        uint256 _totalSendAmount,
        uint256 _totalReceiveAmount
    );

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     */
    constructor(
        string memory _name,
        address _weth,
        address _controller
    ) BaseIntegration(_name, _weth, _controller) {}

    /* ============ External Functions ============ */

    /**
     * Executes a trade on a supported DEX.
     * @dev
     *
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of reserve asset token sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     * @param _minReceiveQuantity   Min units of wanted token to be received from the exchange
     */
    function trade(
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) external nonReentrant onlyIdea {
        TradeInfo memory tradeInfo =
            _createTradeInfo(name, _sendToken, _receiveToken, _sendQuantity, _minReceiveQuantity);
        _validatePreTradeData(tradeInfo, _sendQuantity);

        // Get spender address from exchange adapter and invoke approve for exact amount on sendToken
        tradeInfo.strategy.invokeApprove(_getSpender(), tradeInfo.sendToken, tradeInfo.totalSendQuantity);
        (address targetExchange, uint256 callValue, bytes memory methodData) =
            _getTradeCallData(tradeInfo.sendToken, tradeInfo.totalSendQuantity, tradeInfo.receiveToken);
        tradeInfo.strategy.invokeFromIntegration(targetExchange, callValue, methodData);

        uint256 exchangedQuantity = _validatePostTrade(tradeInfo);
        uint256 newAmountSendTokens = tradeInfo.preTradeSendTokenBalance.sub(tradeInfo.totalSendQuantity);
        uint256 newAmountReceiveTokens = tradeInfo.preTradeReceiveTokenBalance.add(exchangedQuantity);
        emit ComponentExchanged(
            tradeInfo.garden,
            tradeInfo.strategy,
            _sendToken,
            _receiveToken,
            tradeInfo.exchangeName,
            newAmountSendTokens,
            newAmountReceiveTokens
        );
    }

    /* ============ Internal Functions ============ */

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
    ) internal view returns (TradeInfo memory) {
        TradeInfo memory tradeInfo;

        tradeInfo.strategy = IStrategy(msg.sender);
        tradeInfo.garden = IGarden(tradeInfo.strategy.garden());

        tradeInfo.exchangeName = _exchangeName;

        tradeInfo.sendToken = _sendToken;
        tradeInfo.receiveToken = _receiveToken;

        tradeInfo.gardenTotalSupply = tradeInfo.garden.totalSupply();

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
        require(_tradeInfo.totalSendQuantity > 0, 'Token to sell must be nonzero');
        address pair =
            UniswapV2Library.pairFor(
                IBabController(controller).getUniswapFactory(),
                _tradeInfo.sendToken,
                _tradeInfo.receiveToken
            );
        uint256 minLiquidity = _tradeInfo.garden.minLiquidityAsset();
        // Check that there is enough liquidity
        (uint256 liquidity0, uint256 liquidity1, ) = IUniswapV2Pair(pair).getReserves();
        require(
            (IUniswapV2Pair(pair).token0() == weth && liquidity0 >= minLiquidity) ||
                (IUniswapV2Pair(pair).token1() == weth && liquidity1 >= minLiquidity),
            'Not enough liquidity'
        );
        require(
            IERC20(_tradeInfo.sendToken).balanceOf(msg.sender) >= _sendQuantity,
            'Garden needs to have enough liquid tokens'
        );
    }

    /**
     * Validate post trade data.
     *
     * @param _tradeInfo                Struct containing trade information used in internal functions
     * @return uint256                  Total quantity of receive token that was exchanged
     */
    function _validatePostTrade(TradeInfo memory _tradeInfo) internal view returns (uint256) {
        uint256 exchangedQuantity =
            IERC20(_tradeInfo.receiveToken).balanceOf(address(_tradeInfo.strategy)).sub(
                _tradeInfo.preTradeReceiveTokenBalance
            );
        require(exchangedQuantity >= _tradeInfo.totalMinReceiveQuantity, 'Slippage greater than allowed');

        return exchangedQuantity;
    }

    /**
     * Return exchange calldata which is already generated from the exchange API
     *
     * hparam _sendToken            Address of the token to be sent to the exchange
     * hparam _sendQuantity         Units of reserve asset token sent to the exchange
     * hparam _receiveToken         Address of the token that will be received from the exchange
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getTradeCallData(
        address, /* _sendToken */
        uint256, /*_sendQuantity */
        address /* _receiveToken */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        );

    /**
     * Returns the address to approve source tokens to for trading. This is the TokenTaker address
     *
     * @return address     Address of the contract to approve tokens to
     */
    function _getSpender() internal view virtual returns (address);
}
