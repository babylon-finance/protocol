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
pragma abicoder v2;

import {IBabController} from '../../interfaces/IBabController.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {ICurveAddressProvider} from '../../interfaces/external/curve/ICurveAddressProvider.sol';
import {ICurveRegistry} from '../../interfaces/external/curve/ICurveRegistry.sol';

import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';

import {TradeIntegration} from './TradeIntegration.sol';

/**
 * @title CurveTradeIntegration
 * @author Babylon Finance Protocol
 *
 * Curve trade integration
 */
contract CurveTradeIntegration is TradeIntegration {
    using SafeMath for uint256;

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    /* ============ Constants ============ */

    address private constant tricurvePool = 0x80466c64868E1ab14a1Ddf27A676C3fcBE638Fe5;
    // Address of Curve Registry
    ICurveAddressProvider internal constant curveAddressProvider =
        ICurveAddressProvider(0x0000000022D53366457F9d5E68Ec105046FC4383);

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) TradeIntegration('curve_trade', _controller) {}

    /* ============ Internal Functions ============ */

    /**
     * Executes the trade through curve.
     *
     * hparam _strategy             Address of the strategy
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of reserve asset token sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     */
    function _getTradeCallData(
        address, /* _strategy */
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        ICurveRegistry curveRegistry = ICurveRegistry(curveAddressProvider.get_registry());
        (address curvePool, address realSendToken, address realReceiveToken) =
            _getPoolAndTokens(_sendToken, _receiveToken);
        require(curvePool != address(0), 'No curve pool to trade the pair');
        (int128 i, int128 j, bool underlying) =
            curveRegistry.get_coin_indices(curvePool, realSendToken, realReceiveToken);
        bytes memory methodData =
            abi.encodeWithSignature('exchange(int128,int128,uint256,uint256)', i, j, _sendQuantity, 1);
        if (tricurvePool == curvePool) {
            if (realSendToken == ETH_ADD_CURVE) {
                methodData = abi.encodeWithSignature(
                    'exchange(uint256,uint256,uint256,uint256,bool)',
                    i,
                    j,
                    _sendQuantity,
                    1,
                    true
                );
            } else {
                methodData = abi.encodeWithSignature(
                    'exchange(uint256,uint256,uint256,uint256)',
                    i,
                    j,
                    _sendQuantity,
                    1
                );
            }
        }
        if (underlying) {
            methodData = abi.encodeWithSignature(
                'exchange_underlying(int128,int128,uint256,uint256)',
                i,
                j,
                _sendQuantity,
                1
            );
        }
        return (curvePool, realSendToken == ETH_ADD_CURVE ? _sendQuantity : 0, methodData);
    }

    /**
     * Returns the address to approve source tokens to for trading. This is the TokenTaker address
     *
     * @return address             Address of the contract to approve tokens to
     */
    function _getSpender(address _swapTarget) internal pure override returns (address) {
        return _swapTarget;
    }

    /**
     * Checks liquidity of the trade
     *
     * hparam _tradeInfo            Struct containing trade information used in internal functions
     * hparam _sendQuantity         Units of token in SetToken sent to the exchange
     */
    function _checkLiquidity(
        TradeInfo memory, /* _tradeInfo */
        uint256 /* _sendQuantity */
    ) internal pure override returns (bool) {
        // address reserveAsset = _tradeInfo.garden.reserveAsset();
        // uint256 minLiquidityReserveAsset = _tradeInfo.garden.minLiquidityAsset();
        // TODO: Check
        return true;
    }

    /**
     * Return pre action calldata
     *
     * @param  _sendToken               Address of the asset to send
     * hparam  _receiveToken            Address of the asset to receive
     * @param  _sendQuantity            Amount of the asset to send
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPreActionCallData(
        address _sendToken,
        address _receiveToken,
        uint256 _sendQuantity
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        // Unwrap WETH to ETH
        (, address _realSendToken, ) = _getPoolAndTokens(_sendToken, _receiveToken);
        if (_realSendToken == ETH_ADD_CURVE) {
            bytes memory methodData = abi.encodeWithSignature('withdraw(uint256)', _sendQuantity);
            return (WETH, 0, methodData);
        }
        return (address(0), 0, bytes(''));
    }

    /**
     * Return post action calldata
     *
     * hparam  _sendToken               Address of the asset to send
     * @param  _receiveToken            Address of the asset to receive
     * @param  _sendQuantity            Amount of the asset to send
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPostActionCallData(
        address _sendToken,
        address _receiveToken,
        uint256 _sendQuantity
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        // Wrap ETH to WETH
        (, , address _realReceiveToken) = _getPoolAndTokens(_sendToken, _receiveToken);
        if (_realReceiveToken == ETH_ADD_CURVE) {
            bytes memory methodData = abi.encodeWithSignature('deposit()');
            return (WETH, _sendQuantity, methodData);
        }
        return (address(0), 0, bytes(''));
    }

    function _getPostActionToken(
        address /* _receiveToken */
    ) internal pure override returns (address) {
        return ETH_ADD_CURVE;
    }

    /* ============ Private Functions ============ */

    function _getPoolAndTokens(address _sendToken, address _receiveToken)
        private
        view
        returns (
            address,
            address,
            address
        )
    {
        ICurveRegistry curveRegistry = ICurveRegistry(curveAddressProvider.get_registry());
        address curvePool = curveRegistry.find_pool_for_coins(_sendToken, _receiveToken, 0);
        if (_sendToken == WETH && curvePool == address(0)) {
            _sendToken = ETH_ADD_CURVE;
            curvePool = curveRegistry.find_pool_for_coins(ETH_ADD_CURVE, _receiveToken, 0);
        }
        if (_receiveToken == WETH && curvePool == address(0)) {
            _receiveToken = ETH_ADD_CURVE;
            curvePool = curveRegistry.find_pool_for_coins(_sendToken, ETH_ADD_CURVE, 0);
        }
        return (curvePool, _sendToken, _receiveToken);
    }
}
