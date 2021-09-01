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

pragma solidity 0.7.6;

import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {ITradeIntegration} from '../../interfaces/ITradeIntegration.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {BaseIntegration} from '../BaseIntegration.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';

/**
 * @title TradeIntegration
 * @author Babylon Finance Protocol
 *
 * Base class for integration with trading protocols
 */
abstract contract TradeIntegration is BaseIntegration, ReentrancyGuard, ITradeIntegration {
    using LowGasSafeMath for uint256;
    using SafeCast for uint256;
    using PreciseUnitMath for uint256;

    /* ============ Struct ============ */

    struct TradeInfo {
        IGarden garden; // Garden
        IStrategy strategy; // Strategy
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

    /* ============ Constants ============ */

    uint24 internal constant FEE_LOW = 500;
    uint24 internal constant FEE_MEDIUM = 3000;
    uint24 internal constant FEE_HIGH = 10000;
    IUniswapV3Factory internal constant uniswapFactory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, IBabController _controller) BaseIntegration(_name, _controller) {}

    /* ============ External Functions ============ */

    /**
     * Executes a trade on a supported DEX.
     * @dev
     *
     * @param _strategy             Address of the strategy
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of reserve asset token sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     * @param _minReceiveQuantity   Min units of wanted token to be received from the exchange
     */
    function trade(
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) external override nonReentrant onlySystemContract {
        TradeInfo memory tradeInfo =
            _createTradeInfo(_strategy, name, _sendToken, _receiveToken, _sendQuantity, _minReceiveQuantity);
        _validatePreTradeData(tradeInfo, _sendQuantity);
        // Pre actions
        (address targetAddressP, uint256 callValueP, bytes memory methodDataP) =
            _getPreActionCallData(_sendToken, _receiveToken, _sendQuantity);
        if (targetAddressP != address(0)) {
            // Invoke protocol specific call
            if (_getPreApprovalSpender(targetAddressP) != address(0)) {
                tradeInfo.strategy.invokeApprove(
                    _getPreApprovalSpender(targetAddressP),
                    tradeInfo.sendToken,
                    tradeInfo.totalSendQuantity
                );
            }
            tradeInfo.strategy.invokeFromIntegration(targetAddressP, callValueP, methodDataP);
        }
        // Get spender address from exchange adapter and invoke approve for exact amount on sendToken
        (address targetExchange, uint256 callValue, bytes memory methodData) =
            _getTradeCallData(_strategy, tradeInfo.sendToken, tradeInfo.totalSendQuantity, tradeInfo.receiveToken);
        if (targetExchange != address(0)) {
            // Get spender address from exchange adapter and invoke approve for exact amount on sendToken
            tradeInfo.strategy.invokeApprove(
                _getSpender(targetExchange),
                tradeInfo.sendToken,
                tradeInfo.totalSendQuantity
            );
            tradeInfo.strategy.invokeFromIntegration(targetExchange, callValue, methodData);
        }
        // Post actions
        uint256 receiveTokenAmount = _getTokenOrETHBalance(address(_strategy), _getPostActionToken(_receiveToken));
        (targetAddressP, callValueP, methodDataP) = _getPostActionCallData(
            _sendToken,
            _receiveToken,
            receiveTokenAmount
        );
        if (targetAddressP != address(0)) {
            // Invoke protocol specific call
            if (_getPostApprovalSpender(targetAddressP) != address(0)) {
                tradeInfo.strategy.invokeApprove(
                    _getPostApprovalSpender(targetAddressP),
                    _getPostActionToken(_receiveToken),
                    receiveTokenAmount
                );
            }
            // Invoke protocol specific call
            tradeInfo.strategy.invokeFromIntegration(targetAddressP, callValueP, methodDataP);
        }

        uint256 exchangedQuantity = _validatePostTrade(tradeInfo);
        uint256 newSendTokens = tradeInfo.preTradeSendTokenBalance.sub(tradeInfo.totalSendQuantity);
        emit ComponentExchanged(
            tradeInfo.garden,
            tradeInfo.strategy,
            _sendToken,
            _receiveToken,
            tradeInfo.exchangeName,
            newSendTokens,
            exchangedQuantity
        );
    }

    /* ============ Internal Functions ============ */

    /**
     * Create and return TradeInfo struct
     *
     * @param _strategy             Address of the strategy
     * @param _exchangeName         Human readable name of the exchange in the integrations registry
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     * @param _sendQuantity         Units of token in SetToken sent to the exchange
     * @param _minReceiveQuantity   Min units of token in SetToken to be received from the exchange
     *
     * return TradeInfo             Struct containing data for trade
     */
    function _createTradeInfo(
        address _strategy,
        string memory _exchangeName,
        address _sendToken,
        address _receiveToken,
        uint256 _sendQuantity,
        uint256 _minReceiveQuantity
    ) internal view returns (TradeInfo memory) {
        TradeInfo memory tradeInfo;

        tradeInfo.strategy = IStrategy(_strategy);
        tradeInfo.garden = tradeInfo.strategy.garden();

        tradeInfo.exchangeName = _exchangeName;

        tradeInfo.sendToken = _sendToken;
        tradeInfo.receiveToken = _receiveToken;

        tradeInfo.gardenTotalSupply = ERC20(address(tradeInfo.strategy.garden())).totalSupply();

        tradeInfo.totalSendQuantity = _sendQuantity;

        tradeInfo.totalMinReceiveQuantity = _minReceiveQuantity;
        tradeInfo.preTradeSendTokenBalance = ERC20(_sendToken).balanceOf(_strategy);
        tradeInfo.preTradeReceiveTokenBalance = ERC20(_receiveToken).balanceOf(_strategy);
        return tradeInfo;
    }

    /**
     * Validate pre trade data. Check exchange is valid, token quantity is valid.
     *
     * @param _tradeInfo            Struct containing trade information used in internal functions
     * @param _sendQuantity         Amount of tokens sent
     */
    function _validatePreTradeData(TradeInfo memory _tradeInfo, uint256 _sendQuantity) internal view {
        require(_tradeInfo.totalSendQuantity > 0, 'Token to sell must be nonzero');
        require(
            ERC20(_tradeInfo.sendToken).balanceOf(address(_tradeInfo.strategy)) >= _sendQuantity,
            'Strategy needs to have enough liquid tokens'
        );
        require(_checkLiquidity(_tradeInfo, _sendQuantity), 'Not enough liquidity');
    }

    /**
     * Validate post trade data.
     *
     * @param _tradeInfo                Struct containing trade information used in internal functions
     * @return uint256                  Total quantity of receive token that was exchanged
     */
    function _validatePostTrade(TradeInfo memory _tradeInfo) internal view returns (uint256) {
        uint256 exchangedQuantity =
            ERC20(_tradeInfo.receiveToken).balanceOf(address(_tradeInfo.strategy)).sub(
                _tradeInfo.preTradeReceiveTokenBalance
            );
        uint256 spentAmount =
            _tradeInfo.preTradeSendTokenBalance.sub(
                ERC20(_tradeInfo.sendToken).balanceOf(address(_tradeInfo.strategy))
            );
        require(exchangedQuantity >= _tradeInfo.totalMinReceiveQuantity, 'Slippage greater than allowed');
        require(
            spentAmount.add(spentAmount.preciseMul(5e16)) >= _tradeInfo.totalSendQuantity,
            'Not all trade amount spent, partial liquidity'
        );
        return exchangedQuantity;
    }

    /**
     * Return exchange calldata which is already generated from the exchange API
     *
     * hparam _strategy             Address of the strategy
     * hparam _sendToken            Address of the token to be sent to the exchange
     * hparam _sendQuantity         Units of reserve asset token sent to the exchange
     * hparam _receiveToken         Address of the token that will be received from the exchange
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getTradeCallData(
        address, /* _strategy */
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
     * Checks liquidity of the trade. Reverts if not enough
     *
     * hparam _tradeInfo               Trade Info
     * hparam _sendQuantity            Amount of send tokens to exchange
     *
     */
    function _checkLiquidity(
        TradeInfo memory, /* _tradeInfo */
        uint256 /*_sendQuantity */
    ) internal view virtual returns (bool);

    /**
     * Return pre action calldata
     *
     * hparam  _sendToken               Address of the asset to send
     * hparam  _receiveToken            Address of the asset to receive
     * hparam  _sendQuantity            Amount of the asset to send
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPreActionCallData(
        address, /* _sendToken */
        address, /* _receiveToken */
        uint256 /* _sendQuantity */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        return (address(0), 0, bytes(''));
    }

    /**
     * Return pre action calldata
     *
     * hparam  _sendToken               Address of the asset to send
     * hparam  _receiveToken            Address of the asset to receive
     * hparam  _sendQuantity            Amount of the asset to send
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPostActionCallData(
        address, /* _sendToken */
        address, /* _receiveToken */
        uint256 /* _sendQuantity */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        return (address(0), 0, bytes(''));
    }

    /**
     * Returns the address to approve source tokens to for trading. This is the TokenTaker address
     *
     * @param _swapTarget      Address of the contracts that executes the swap
     * @return address         Address of the contract to approve tokens to
     */
    function _getSpender(address _swapTarget) internal view virtual returns (address);

    /**
     * Returns the address to approve the pre action. This is the TokenTaker address
     *
     * @param _swapTarget      Address of the contracts that executes the swap
     * @return address         Address of the contract to approve tokens to
     */
    function _getPreApprovalSpender(address _swapTarget) internal view virtual returns (address) {
        return address(0);
    }

    /**
     * Returns the address to approve the post action. This is the TokenTaker address
     *
     * @param _swapTarget      Address of the contracts that executes the swap
     * @return address         Address of the contract to approve tokens to
     */
    function _getPostApprovalSpender(address _swapTarget) internal view virtual returns (address) {
        return address(0);
    }

    function _getPostActionToken(address _receiveToken) internal view virtual returns (address) {
        return _receiveToken;
    }
}
