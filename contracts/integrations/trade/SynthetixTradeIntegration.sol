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

import 'hardhat/console.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {ISynthetix} from '../../interfaces/external/synthetix/ISynthetix.sol';
import {ISnxProxy} from '../../interfaces/external/synthetix/ISnxProxy.sol';
import {ISnxSynth} from '../../interfaces/external/synthetix/ISnxSynth.sol';
import {ISnxEtherWrapper} from '../../interfaces/external/synthetix/ISnxEtherWrapper.sol';
import {ISnxDepot} from '../../interfaces/external/synthetix/ISnxDepot.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';

import {TradeIntegration} from './TradeIntegration.sol';

/**
 * @title SynthetixTradeIntegration
 * @author Babylon Finance Protocol
 *
 * Synthethix trade integration
 */
contract SynthetixTradeIntegration is TradeIntegration {
    using SafeMath for uint256;

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */
    /* ============ Constants ============ */
    ISnxEtherWrapper internal constant snxEtherWrapper = ISnxEtherWrapper(0xC1AAE9d18bBe386B102435a8632C8063d31e747C);
    ISnxDepot internal constant snxDepot = ISnxDepot(0xE1f64079aDa6Ef07b03982Ca34f1dD7152AA3b86);

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) TradeIntegration('synthetix_trade', _controller) {}

    /* ============ Internal Functions ============ */

    /**
     * Executes the trade through synthetix.
     *
     * @param _strategy             Address of the strategy
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of reserve asset token sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     */
    function _getTradeCallData(
        address _strategy,
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
        (address sendTokenImpl, address receiveTokenImpl) = _getTokens(_sendToken, _receiveToken, _sendQuantity);
        require(sendTokenImpl != address(0) && receiveTokenImpl != address(0), 'Syntetix needs synth or WETH');
        if (sendTokenImpl == receiveTokenImpl) {
          return (address(0), 0, bytes(''));
        }
        bytes memory methodData =
            abi.encodeWithSignature(
                'exchange(bytes32,uint256,bytes32)',
                ISnxSynth(sendTokenImpl).currencyKey(),
                _sendQuantity,
                ISnxSynth(receiveTokenImpl).currencyKey()
            );
        return (ISnxProxy(SNX).target(), 0, methodData);
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
        if (_sendToken == WETH) {
            if (snxEtherWrapper.capacity() >= _sendQuantity) {
              // Mint sETH from WETH
              bytes memory methodData = abi.encodeWithSignature('mint(uint256)', _sendQuantity);
              return (address(snxEtherWrapper), 0, methodData);
            } else {
              bytes memory methodData = abi.encodeWithSignature('exchangeEtherForSynths()');
              return (address(snxDepot), _sendQuantity, methodData);
            }
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
        // Burn sETH to WETH if needed
        if (_receiveToken == WETH) {
            bytes memory methodData = abi.encodeWithSignature('burn(uint256)', _sendQuantity);
            return (address(snxEtherWrapper), 0, methodData);
        }
        return (address(0), 0, bytes(''));
    }

    /**
     * Returns the address to approve source tokens to for trading. This is the TokenTaker address
     *
     * @param _swapTarget          Address of the contract that will execute the swap
     * @return address             Address of the contract to approve tokens to
     */
    function _getSpender(address _swapTarget) internal view override returns (address) {
        return _swapTarget;
    }

    /**
     * Returns the address to approve the pre action. This is the TokenTaker address
     *
     * @param _swapTarget          Address of the contract that will execute the swap
     * @return address             Address of the contract to approve tokens to
     */
    function _getPreApprovalSpender(address _swapTarget) internal view override returns (address) {
        return _swapTarget == address(snxDepot) ? address(0) : _swapTarget;
    }

    /**
     * Checks liquidity of the trade
     *
     * @param _tradeInfo            Struct containing trade information used in internal functions
     * @param _sendQuantity         Units of token in SetToken sent to the exchange
     */
    function _checkLiquidity(TradeInfo memory _tradeInfo, uint256 _sendQuantity) internal view override returns (bool) {
        address reserveAsset = _tradeInfo.garden.reserveAsset();
        uint256 minLiquidityReserveAsset = _tradeInfo.garden.minLiquidityAsset();
        // TODO: Check
        return true;
    }

    /* ============ Private Functions ============ */

    function _getTokens(address _sendToken, address _receiveToken, uint256 _sendQuantity)
        private
        view
        returns (
            address,
            address
        )
    {
        ISynthetix synthetix = ISynthetix(ISnxProxy(SNX).target());
        if (_sendToken == WETH) {
            _sendToken = snxEtherWrapper.capacity() >= _sendQuantity ? sETH : sUSD;
        }
        if (_receiveToken == WETH) {
            _receiveToken = sETH;
        }
        address sendTokenImpl;
        address receiveTokenImpl;
        try ISnxProxy(_sendToken).target() returns(address impl) {
          sendTokenImpl = impl;
        } catch {
          sendTokenImpl = address(0);
        }
        try ISnxProxy(_receiveToken).target() returns(address impl) {
          receiveTokenImpl = impl;
        } catch {
          receiveTokenImpl = address(0);
        }
        return (sendTokenImpl, receiveTokenImpl);
    }
}
