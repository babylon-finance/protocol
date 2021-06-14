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
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {IPriceOracle} from '../../interfaces/IPriceOracle.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {ITradeIntegration} from '../../interfaces/ITradeIntegration.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {BaseIntegration} from '../BaseIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';

/**
 * @title BorrowIntetration
 * @author Babylon Finance Protocol
 *
 * Base class for integration with trading protocols
 */
abstract contract TradeIntegration is BaseIntegration, ReentrancyGuard, ITradeIntegration {
    using SafeMath for uint256;
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

    uint24 private constant FEE_LOW = 500;
    uint24 private constant FEE_MEDIUM = 3000;
    uint24 private constant FEE_HIGH = 10000;

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
        IBabController _controller
    ) BaseIntegration(_name, _weth, _controller) {}

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
        // Get spender address from exchange adapter and invoke approve for exact amount on sendToken
        tradeInfo.strategy.invokeApprove(_getSpender(), tradeInfo.sendToken, tradeInfo.totalSendQuantity);
        (address targetExchange, uint256 callValue, bytes memory methodData) =
            _getTradeCallData(_strategy, tradeInfo.sendToken, tradeInfo.totalSendQuantity, tradeInfo.receiveToken);
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
     * @param _sendQuantity         Units of token in SetToken sent to the exchange
     */
    function _validatePreTradeData(TradeInfo memory _tradeInfo, uint256 _sendQuantity) internal view {
        require(_tradeInfo.totalSendQuantity > 0, 'Token to sell must be nonzero');
        address reserveAsset = _tradeInfo.garden.reserveAsset();
        uint256 liquidityInReserve = _getUniswapHighestLiquidity(_tradeInfo, reserveAsset);
        uint256 minLiquidityReserveAsset = _tradeInfo.garden.minLiquidityAsset();
        require(liquidityInReserve >= minLiquidityReserveAsset, 'Not enough liquidity');
        require(
            ERC20(_tradeInfo.sendToken).balanceOf(address(_tradeInfo.strategy)) >= _sendQuantity,
            'Garden needs to have enough liquid tokens'
        );
    }

    function _getUniswapHighestLiquidity(TradeInfo memory _tradeInfo, address _reserveAsset)
        internal
        view
        returns (uint256)
    {
        address sendToken = _getReserveAsWeth(_tradeInfo.sendToken, _reserveAsset);
        address receiveToken = _getReserveAsWeth(_tradeInfo.receiveToken, _reserveAsset);
        // Exit if going to weth from weth
        if (sendToken == receiveToken) {
            return _tradeInfo.garden.minLiquidityAsset();
        }
        IUniswapV3Pool pool = _getUniswapPoolWithHighestLiquidity(sendToken, receiveToken);
        uint256 poolLiquidity = uint256(pool.liquidity());
        uint256 liquidityInReserve;
        if (pool.token0() == weth) {
            liquidityInReserve = poolLiquidity.mul(poolLiquidity).div(ERC20(pool.token1()).balanceOf(address(pool)));
        }
        if (pool.token1() == weth) {
            liquidityInReserve = poolLiquidity.mul(poolLiquidity).div(ERC20(pool.token0()).balanceOf(address(pool)));
        }
        // Normalize to reserve asset
        if (weth != _reserveAsset) {
            IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
            uint256 price = oracle.getPrice(weth, _reserveAsset);
            liquidityInReserve = liquidityInReserve.preciseMul(price);
        }
        return liquidityInReserve;
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
        // Get reserve asset decimals
        uint8 tokenDecimals = ERC20(_tradeInfo.receiveToken).decimals();
        uint256 normalizedExchangedQuantity =
            tokenDecimals != 18 ? exchangedQuantity.mul(10**(18 - tokenDecimals)) : exchangedQuantity;
        require(normalizedExchangedQuantity >= _tradeInfo.totalMinReceiveQuantity, 'Slippage greater than allowed');

        return normalizedExchangedQuantity;
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
     * Returns the address to approve source tokens to for trading. This is the TokenTaker address
     *
     * @return address     Address of the contract to approve tokens to
     */
    function _getSpender() internal view virtual returns (address);

    function _getUniswapPoolWithHighestLiquidity(address sendToken, address receiveToken)
        private
        view
        returns (IUniswapV3Pool)
    {
        IUniswapV3Factory factory = IUniswapV3Factory(IBabController(controller).uniswapFactory());
        IUniswapV3Pool poolLow = IUniswapV3Pool(factory.getPool(sendToken, receiveToken, FEE_LOW));
        IUniswapV3Pool poolMedium = IUniswapV3Pool(factory.getPool(sendToken, receiveToken, FEE_MEDIUM));
        IUniswapV3Pool poolHigh = IUniswapV3Pool(factory.getPool(sendToken, receiveToken, FEE_HIGH));

        uint128 liquidityLow = poolLow.liquidity();
        uint128 liquidityMedium = poolMedium.liquidity();
        uint128 liquidityHigh = poolHigh.liquidity();
        if (liquidityLow > liquidityMedium && liquidityLow >= liquidityHigh) {
            return poolLow;
        }
        if (liquidityMedium > liquidityLow && liquidityMedium >= liquidityHigh) {
            return poolMedium;
        }
        return poolHigh;
    }

    function _getReserveAsWeth(address _token, address _reserveAsset) private view returns (address) {
        return _reserveAsset == _token ? weth : _token;
    }
}
