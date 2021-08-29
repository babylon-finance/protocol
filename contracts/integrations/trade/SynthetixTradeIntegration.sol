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
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
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

    address private constant curvesUSD = 0xA5407eAE9Ba41422680e2e00537571bcC53efBfD;

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
        (address sendTokenImpl, address receiveTokenImpl, uint256 realSendAmount) = _getTokens(_sendToken, _receiveToken, _sendQuantity, _strategy);
        require(sendTokenImpl != address(0) && receiveTokenImpl != address(0), 'Syntetix needs synth or DAI or USDC');
        if (sendTokenImpl == receiveTokenImpl) {
          return (address(0), 0, bytes(''));
        }
        console.log('realSendAmount', realSendAmount, sendTokenImpl, receiveTokenImpl);
        console.log(uint(ISnxSynth(sendTokenImpl).currencyKey()), uint(ISnxSynth(receiveTokenImpl).currencyKey()));
        bytes memory methodData =
            abi.encodeWithSignature(
                'exchange(bytes32,uint256,bytes32)',
                ISnxSynth(sendTokenImpl).currencyKey(),
                realSendAmount,
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
        if (_sendToken == DAI) {
          bytes memory methodData =
              abi.encodeWithSignature('exchange(int128,int128,uint256,uint256)', 0, 3, _sendQuantity, 1);
          return (curvesUSD, 0, methodData);
        }
        if (_sendToken == USDC) {
          bytes memory methodData =
              abi.encodeWithSignature('exchange(int128,int128,uint256,uint256)', 0, 1, _sendQuantity, 1);
          return (curvesUSD, 0, methodData);
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
        if (_receiveToken == DAI) {
          bytes memory methodData =
              abi.encodeWithSignature('exchange(int128,int128,uint256,uint256)', 3, 0, _sendQuantity, 1);
          return (curvesUSD, 0, methodData);
        }
        if (_receiveToken == USDC) {
          bytes memory methodData =
              abi.encodeWithSignature('exchange(int128,int128,uint256,uint256)', 1, 0, _sendQuantity, 1);
          return (curvesUSD, 0, methodData);
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
        return _swapTarget;
    }

    /**
     * Returns the address to approve the post action. This is the TokenTaker address
     *
     * @param _swapTarget          Address of the contract that will execute the swap
     * @return address             Address of the contract to approve tokens to
     */
    function _getPostApprovalSpender(address _swapTarget) internal view override returns (address) {
        return _swapTarget;
    }

    function _getPostActionToken(address _receiveToken) internal view override returns (address) {
      if (_receiveToken == DAI || _receiveToken == USDC) {
          return sUSD;
      }
      return _receiveToken;
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

    function _getTokens(address _sendToken, address _receiveToken, uint256 _sendQuantity, address _strategy)
        private
        view
        returns (
            address,
            address,
            uint256
        )
    {
        ISynthetix synthetix = ISynthetix(ISnxProxy(SNX).target());
        if (_sendToken == DAI || _sendToken == USDC) {
            _sendToken = sUSD;
        }
        if (_receiveToken == DAI || _receiveToken == USDC) {
            _receiveToken = sUSD;
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
        console.log('addresses', sendTokenImpl, receiveTokenImpl);
        return (sendTokenImpl, receiveTokenImpl, ERC20(_sendToken).balanceOf(_strategy));
    }
}
