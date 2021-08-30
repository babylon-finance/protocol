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

import 'hardhat/console.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import {ICurveAddressProvider} from '../../interfaces/external/curve/ICurveAddressProvider.sol';
import {ICurveRegistry} from '../../interfaces/external/curve/ICurveRegistry.sol';
import {ISynthetix} from '../../interfaces/external/synthetix/ISynthetix.sol';
import {ISnxProxy} from '../../interfaces/external/synthetix/ISnxProxy.sol';
import {ITradeIntegration} from '../../interfaces/ITradeIntegration.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {BaseIntegration} from '../BaseIntegration.sol';

import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';

/**
 * @title MasterSwapper
 * @author Babylon Finance Protocol
 *
 * Master class for integration with trading protocols
 */

// - MasterSwapper
//   * Uni V2 TWAP
//   * Synthetix Contract. Exchange
//     Support proxy or no proxy between synths
//     - Only between pairs of synths. Great for bigger trades
//
// * Implement CurveTradeIntegration
// * Implement SynthetixTradeIntegration
// * Implemen  UniswapV2TradeIntegration
contract MasterSwapper is BaseIntegration, ReentrancyGuard, ITradeIntegration {
    using LowGasSafeMath for uint256;
    using SafeCast for uint256;
    using PreciseUnitMath for uint256;

    /* ============ Struct ============ */

    struct TradeInfo {
        IGarden garden; // Garden
        address strategy; // Strategy
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

    /* ============ Constants ============ */

    IUniswapV3Factory internal constant uniswapFactory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    ICurveAddressProvider internal constant curveAddressProvider =
        ICurveAddressProvider(0x0000000022D53366457F9d5E68Ec105046FC4383);

    ITradeIntegration internal immutable curve;
    ITradeIntegration internal immutable univ3;
    ITradeIntegration internal immutable synthetix;

    /* ============ Constructor ============ */

    /**
     * Creates the master swapper
     *
     * @param _controller             Address of the controller
     * @param _curve                  Address of curve trade integration
     * @param _univ3                  Address of uni trade integration
     * @param _synthetix              Address of synthetix trade integration
     */
    constructor(
        IBabController _controller,
        ITradeIntegration _curve,
        ITradeIntegration _univ3,
        ITradeIntegration _synthetix
    ) BaseIntegration('master swapper', _controller) {
        curve = _curve;
        univ3 = _univ3;
        synthetix = _synthetix;
    }

    /* ============ External Functions ============ */

    /**
     * Executes a trade choosing the appropriate protocol for it
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
    ) external override nonReentrant {
        if (_sendToken == _receiveToken) {
            return;
        }
        console.log('enter');
        // Synthetix Direct
        address _sendTokenSynth = _getSynth(_sendToken);
        address _receiveTokenSynth = _getSynth(_receiveToken);
        console.log('synthetix');
        if ((_sendTokenSynth != address(0) && _receiveTokenSynth != address(0)) ||
            (_sendTokenSynth != address(0) && (_receiveToken == DAI || _receiveToken == USDC)) ||
            (_receiveToken != address(0) && (_sendTokenSynth == DAI || _sendTokenSynth == USDC))) {
            try
                ITradeIntegration(synthetix).trade(
                    _strategy,
                    _sendToken,
                    _sendQuantity,
                    _receiveToken,
                    _minReceiveQuantity
                )
            {
              return;
            } catch {
            }
        }
        console.log('before curve');
        // Curve Direct
        if (_curveSwap(_strategy, _sendToken, _receiveToken, _sendQuantity, _minReceiveQuantity)) {
            return;
        }
        console.log('after curve');
        // Abstract Synths out
        if (_sendTokenSynth != address(0)) {
          // Trade to DAI through sUSD
          try
              ITradeIntegration(synthetix).trade(
                  _strategy,
                  _sendToken,
                  _sendQuantity,
                  DAI,
                  1
              )
          {
            // Change DAI to receive token
            // trade(_strategy, DAI, _getTokenOrETHBalance(_strategy, DAI), _receiveToken, _minReceiveQuantity);
            return;
          } catch {
          }
        }
        // Trade to DAI and then do DAI to synh
        if (_receiveTokenSynth != address(0)) {
          // trade(_strategy, _sendToken, _sendQuantity, DAI, 1);
          try
              ITradeIntegration(synthetix).trade(
                  _strategy,
                  DAI,
                  _getTokenOrETHBalance(_strategy, DAI),
                  _receiveToken,
                  _minReceiveQuantity
              )
          {
            return;
          } catch {
            require(false, "Failed midway in out synth");
          }
        }
        // Go through UNIv3 first
        console.log('uni');
        try
            ITradeIntegration(univ3).trade(
                _strategy,
                _sendToken,
                _sendQuantity,
                _receiveToken,
                _minReceiveQuantity
            )
        {
          console.log('uni worked');
            return;
        } catch {
        }
        console.log('curve reserve');
        // Try Curve through reserve assets
        bool found = _checkCurveRoutesThroughReserve(WETH, _strategy, _sendToken, _receiveToken, _sendQuantity, _minReceiveQuantity);
        if (found) {
          return;
        }
        console.log('dai reserve path');
        found = _checkCurveRoutesThroughReserve(DAI, _strategy, _sendToken, _receiveToken, _sendQuantity, _minReceiveQuantity);
        if (found) {
          return;
        }
        console.log('wbtc reserve path');
        found = _checkCurveRoutesThroughReserve(WBTC, _strategy, _sendToken, _receiveToken, _sendQuantity, _minReceiveQuantity);
        console.log('after wbtc');
        if (found) {
            return;
        }
        if (_minReceiveQuantity == 0) {
            // Try on univ2 (only direct trade)
        }
        require(false, 'Master swapper could not swap');
    }

    /* ============ Internal Functions ============ */

    function _checkCurveRoutesThroughReserve(address _reserve, address _strategy, address _sendToken, address _receiveToken, uint256 _sendQuantity, uint256 _minReceiveQuantity) private returns (bool) {
        uint256 reserveBalance = _getTokenOrETHBalance(_strategy, _reserve);
        bool swapped = false;
        console.log('reserve', _reserve);
        uint diff = reserveBalance;
        // Going through curve but switching first to reserve
        if (_sendToken != _reserve) {
            console.log('2');
            try
                ITradeIntegration(univ3).trade(
                    _strategy,
                    _sendToken,
                    _sendQuantity,
                    _reserve,
                    1 // TODO
                )
            {
                if (_reserve == _receiveToken) {
                    return true;
                }
                diff = _getTokenOrETHBalance(_strategy, _reserve).sub(reserveBalance);
                console.log('swapped');
                swapped = true;
            } catch {
              console.log('uni failed', _sendToken, _reserve);
            }
        }
        console.log('before diff');
        console.log('same', _sendToken, _reserve, swapped);
        if (_sendToken == _reserve || swapped) {
            console.log('eooo', diff);
            if (
                _curveSwap(
                    _strategy,
                    _reserve,
                    _receiveToken,
                    diff,
                    _minReceiveQuantity
                )
            ) {
                return true;
            }
            if (swapped) {
                require(false, 'Curve Swap failed midway');
            }
        }
        // Going through curve to reserve and then receive Token
        if (_sendToken != _reserve) {
            swapped = false;
            reserveBalance = _getTokenOrETHBalance(_strategy, _reserve);
            if (_curveSwap(_strategy, _sendToken, _reserve, _sendQuantity, 1)) {
                swapped = true;
                diff = _getTokenOrETHBalance(_strategy, _reserve).sub(reserveBalance);
                if (_reserve == _receiveToken) {
                    return true;
                }
            }
        }
        if (_sendToken == _reserve || swapped) {
            console.log('balance', diff);
            try
                ITradeIntegration(univ3).trade(
                    _strategy,
                    _reserve,
                    diff,
                    _receiveToken,
                    _minReceiveQuantity
                )
            {
                return true;
            } catch {
                if (swapped) {
                    require(false, 'Uni Swap failed midway');
                }
            }
        }
        return false;
    }

    function _curveSwap(
        address _strategy,
        address _fromToken,
        address _toToken,
        uint256 _sendTokenAmount,
        uint256 _minReceiveQuantity
    ) private returns (bool) {
        ICurveRegistry curveRegistry = ICurveRegistry(curveAddressProvider.get_registry());
        console.log('in curve swap', _fromToken, _toToken);
        address curvePool = curveRegistry.find_pool_for_coins(_fromToken, _toToken);
        if (curvePool == address(0) && _fromToken == WETH) {
            curvePool = curveRegistry.find_pool_for_coins(ETH_ADD_CURVE, _toToken);
        }
        if (curvePool == address(0) && _toToken == WETH) {
            curvePool = curveRegistry.find_pool_for_coins(_fromToken, ETH_ADD_CURVE);
        }
        console.log('curvePool', curvePool);
        if (curvePool != address(0)) {
            try ITradeIntegration(curve).trade(_strategy, _fromToken, _sendTokenAmount, _toToken, _minReceiveQuantity) {
                return true;
            } catch {
                return false;
            }
        }
        return false;
    }

    function _getSynth(address _token) private view returns (address) {
        ISynthetix synthetix = ISynthetix(ISnxProxy(SNX).target());
        // try ISnxProxy(_token).target() returns (address tokenImpl) {
        //     return tokenImpl;
        //     // return uint256(synthetix.synthsByAddress(tokenImpl)) != 0 ? tokenImpl : address(0);
        // } catch {
        // }
        return address(0);
    }
}
