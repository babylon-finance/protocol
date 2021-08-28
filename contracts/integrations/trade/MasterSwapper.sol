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
        TradeInfo memory tradeInfo =
            _createTradeInfo(_strategy, name, _sendToken, _receiveToken, _sendQuantity, _minReceiveQuantity);
        // Go through UNIv3 first
        try
            ITradeIntegration(univ3).trade(
                tradeInfo.strategy,
                _sendToken,
                _sendQuantity,
                tradeInfo.receiveToken,
                tradeInfo.totalMinReceiveQuantity
            )
        {
            return;
        } catch {
          // Try Curve
          console.log('checking curve');
          bool found = _checkAllCurvePaths(tradeInfo);
          if (found) {
              return;
          }
          // Try Synthetix
          address _sendTokenSynth = _getSynth(_sendToken);
          address _receiveTokenSynth = _getSynth(_receiveToken);
          if (_sendTokenSynth != address(0) && _receiveTokenSynth != address(0)) {
              try
                  ITradeIntegration(synthetix).trade(
                      tradeInfo.strategy,
                      _sendToken,
                      _sendQuantity,
                      tradeInfo.receiveToken,
                      tradeInfo.totalMinReceiveQuantity
                  )
              {
                  return;
              } catch {

              }
          } else {
              if (_sendTokenSynth != address(0)) {
                  // Go to sUSD and then swap sUSD to WETH and then WETH to receive
              }
              if (_receiveTokenSynth != address(0)) {
                  // Swap send token to WETH->sUSD-> receive Synth
              }
          }
          if (_minReceiveQuantity == 0) {
              // Try on univ2 (only direct trade)
          }
        }
        require(false, 'Master swapper could not swap');
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

        tradeInfo.strategy = _strategy;
        tradeInfo.garden = IStrategy(tradeInfo.strategy).garden();

        tradeInfo.exchangeName = _exchangeName;

        tradeInfo.sendToken = _sendToken;
        tradeInfo.receiveToken = _receiveToken;

        tradeInfo.gardenTotalSupply = ERC20(address(tradeInfo.garden)).totalSupply();

        tradeInfo.totalSendQuantity = _sendQuantity;

        tradeInfo.totalMinReceiveQuantity = _minReceiveQuantity;

        tradeInfo.preTradeSendTokenBalance = ERC20(_sendToken).balanceOf(_strategy);
        tradeInfo.preTradeReceiveTokenBalance = ERC20(_receiveToken).balanceOf(_strategy);

        return tradeInfo;
    }

    function _checkAllCurvePaths(TradeInfo memory _tradeInfo) private returns (bool) {
        ICurveRegistry curveRegistry = ICurveRegistry(curveAddressProvider.get_registry());
        bool found = false;
        address curvePool = curveRegistry.find_pool_for_coins(_tradeInfo.sendToken, _tradeInfo.receiveToken);
        // Direct pairs via curve
        if (curvePool != address(0)) {
            console.log('direct path');
            ITradeIntegration(curve).trade(
                _tradeInfo.strategy,
                _tradeInfo.sendToken,
                _tradeInfo.totalSendQuantity,
                _tradeInfo.receiveToken,
                _tradeInfo.totalMinReceiveQuantity
            );
            return true;
        }
        console.log('weth reserve path');
        found = _checkCurveRoutesThroughReserve(WETH, _tradeInfo, curveRegistry);
        if (!found) {
            console.log('dai reserve path');
            found = _checkCurveRoutesThroughReserve(DAI, _tradeInfo, curveRegistry);
            if (!found) {
                console.log('wbtc reserve path');
                found = _checkCurveRoutesThroughReserve(WBTC, _tradeInfo, curveRegistry);
                console.log('after wbtc');
            }
        }
        console.log('found', found);
        return found;
    }

    function _checkCurveRoutesThroughReserve(
        address _reserve,
        TradeInfo memory _tradeInfo,
        ICurveRegistry curveRegistry
    ) private returns (bool) {
        uint256 reserveBalance = 0;
        bool swapped = false;
        // Going through curve but switching first to reserve
        if (_tradeInfo.sendToken != _reserve) {
          reserveBalance = _getTokenOrETHBalance(_tradeInfo.strategy, _reserve);
          try
              ITradeIntegration(univ3).trade(
                  _tradeInfo.strategy,
                  _tradeInfo.sendToken,
                  _tradeInfo.totalSendQuantity,
                  _reserve,
                  1
              )
          {
            if (_reserve == _tradeInfo.receiveToken) {
              return true;
            }
            swapped = true;
          } catch {
          }
        }
        if (_tradeInfo.sendToken == _reserve || swapped) {
          address curvePool = curveRegistry.find_pool_for_coins(_reserve, _tradeInfo.receiveToken);
          if (curvePool == address(0) && _reserve == WETH) {
            curvePool = curveRegistry.find_pool_for_coins(ETH_ADD_CURVE, _tradeInfo.receiveToken);
          }
          console.log('direct pool', curvePool, _reserve, _tradeInfo.receiveToken);
          if (curvePool != address(0)) {
            ITradeIntegration(curve).trade(
                _tradeInfo.strategy,
                _reserve,
                _getTokenOrETHBalance(_tradeInfo.strategy, _reserve).sub(reserveBalance),
                _tradeInfo.receiveToken,
                _tradeInfo.totalMinReceiveQuantity
            );
            return true;
          }
        }

        // Going through curve to reserve and then receive Token
        if (_tradeInfo.sendToken != _reserve) {
          swapped = false;
          address curvePool = curveRegistry.find_pool_for_coins(_tradeInfo.sendToken, _reserve);
          if (curvePool == address(0) && _reserve == WETH) {
            curvePool = curveRegistry.find_pool_for_coins(_tradeInfo.sendToken, ETH_ADD_CURVE);
          }
          console.log('inverse pool', curvePool, _tradeInfo.sendToken, _reserve);
          if (curvePool != address(0)) {
              reserveBalance = _getTokenOrETHBalance(_tradeInfo.strategy, _reserve);
              try
                  ITradeIntegration(curve).trade(
                      _tradeInfo.strategy,
                      _tradeInfo.sendToken,
                      _tradeInfo.totalSendQuantity,
                      _reserve,
                      1
                  )
              {
                if (_reserve == _tradeInfo.receiveToken) {
                  return true;
                }
                swapped = true;
              }
              catch {
              }
          }
        }
        if (_tradeInfo.sendToken == _reserve || swapped) {
          console.log('balance', _getTokenOrETHBalance(_tradeInfo.strategy, _reserve).sub(reserveBalance));
          try ITradeIntegration(univ3).trade(
              _tradeInfo.strategy,
              _reserve,
              _getTokenOrETHBalance(_tradeInfo.strategy, _reserve).sub(reserveBalance),
              _tradeInfo.receiveToken,
              _tradeInfo.totalMinReceiveQuantity
          ) {
            return true;
          } catch {
            return false;
          }
        }
        return false;
    }

    function _getTokenOrETHBalance(address _strategy, address _token) private view returns (uint256) {
        if (_token == address(0) || _token == ETH_ADD_CURVE) {
            return _strategy.balance;
        }
        return ERC20(_token).balanceOf(_strategy);
    }

    function _getSynth(address _token) private view returns (address) {
        ISynthetix synthetix = ISynthetix(ISnxProxy(SNX).target());
        try ISnxProxy(_token).target() returns (address tokenImpl) {
          return uint256(synthetix.synthsByAddress(tokenImpl)) != 0 ? tokenImpl : address(0);
        } catch {
          return address(0);
        }
    }
}
