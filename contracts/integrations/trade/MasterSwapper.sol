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
import {ISnxSynth} from '../../interfaces/external/synthetix/ISnxSynth.sol';
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
    ITradeIntegration internal immutable univ2;

    /* ============ Constructor ============ */

    /**
     * Creates the master swapper
     *
     * @param _controller             Address of the controller
     * @param _curve                  Address of curve trade integration
     * @param _univ3                  Address of univ3 trade integration
     * @param _synthetix              Address of synthetix trade integration
     * @param _univ2                  Address of univ2 trade integration
     */
    constructor(
        IBabController _controller,
        ITradeIntegration _curve,
        ITradeIntegration _univ3,
        ITradeIntegration _synthetix,
        ITradeIntegration _univ2
    ) BaseIntegration('master swapper', _controller) {
        curve = _curve;
        univ3 = _univ3;
        synthetix = _synthetix;
        univ2 = _univ2;
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
    ) public override nonReentrant {
        _trade(_strategy, _sendToken, _sendQuantity, _receiveToken, _minReceiveQuantity);
    }

    function _trade(
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) private {
        if (_sendToken == _receiveToken) {
            return;
        }
        console.log('--- TRADE ASSET ---', _sendToken, _receiveToken, ERC20(_sendToken).balanceOf(_strategy));
        // Synthetix Direct
        address _sendTokenSynth = _getSynth(_sendToken);
        address _receiveTokenSynth = _getSynth(_receiveToken);
        if (
            (_sendTokenSynth != address(0) && _receiveTokenSynth != address(0)) ||
            (_sendTokenSynth != address(0) && (_receiveToken == DAI || _receiveToken == USDC)) ||
            (_receiveToken != address(0) && (_sendTokenSynth == DAI || _sendTokenSynth == USDC))
        ) {
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
            } catch {}
        }
        // Curve Direct
        if (_curveSwap(_strategy, _sendToken, _receiveToken, _sendQuantity, _minReceiveQuantity)) {
            return;
        }
        // Abstract Synths out
        if (_sendTokenSynth != address(0)) {
            uint256 reserveBalance = _getTokenOrETHBalance(_strategy, DAI);
            // Trade to DAI through sUSD
            try ITradeIntegration(synthetix).trade(_strategy, _sendToken, _sendQuantity, DAI, 1) {
                // Change DAI to receive token
                _trade(
                    _strategy,
                    DAI,
                    _getTokenOrETHBalance(_strategy, DAI).sub(reserveBalance),
                    _receiveToken,
                    _minReceiveQuantity
                );
                return;
            } catch {
                // console.log('synth to DAI failed');
            }
        }
        // Trade to DAI and then do DAI to synh
        if (_receiveTokenSynth != address(0)) {
            uint256 reserveBalance = 0;

            if (_sendToken != DAI) {
                reserveBalance = _getTokenOrETHBalance(_strategy, DAI);
                _trade(_strategy, _sendToken, _sendQuantity, DAI, 1);
            }
            try
                ITradeIntegration(synthetix).trade(
                    _strategy,
                    DAI,
                    _getTokenOrETHBalance(_strategy, DAI).sub(reserveBalance),
                    _receiveToken,
                    _minReceiveQuantity
                )
            {
                return;
            } catch {
                require(false, 'Failed midway in out synth');
            }
        }
        // Go through UNIv3 first
        try ITradeIntegration(univ3).trade(_strategy, _sendToken, _sendQuantity, _receiveToken, _minReceiveQuantity) {
            return;
        } catch {}
        // Try Curve through reserve assets
        if (_checkCurveThroughReserves([DAI, WETH, WBTC], _strategy, _sendToken, _receiveToken, _sendQuantity, _minReceiveQuantity)) {
          return;
        }
        if (_minReceiveQuantity > 1) {
            // Try on univ2 (only direct trade) through WETH
            ITradeIntegration(univ2).trade(_strategy, _sendToken, _sendQuantity, WETH, 1);
            ITradeIntegration(univ2).trade(
                _strategy,
                WETH,
                _getTokenOrETHBalance(_strategy, WETH),
                _receiveToken,
                _minReceiveQuantity
            );
        }
        require(false, 'Master swapper could not swap');
    }

    /* ============ Internal Functions ============ */

    function _checkCurveThroughReserves(
      address[3] memory _reserves,
      address _strategy,
      address _sendToken,
      address _receiveToken,
      uint256 _sendQuantity,
      uint256 _minReceiveQuantity
    ) private returns (bool) {
      for (uint i = 0; i < _reserves.length; i++) {
        if (_sendToken != _reserves[i]) {
            if (_checkCurveRoutesThroughReserve(
                _reserves[i],
                _strategy,
                _sendToken,
                _receiveToken,
                _sendQuantity,
                _minReceiveQuantity
            )) {
                return true;
            }
        }
      }
      return false;
    }

    function _checkCurveRoutesThroughReserve(
        address _reserve,
        address _strategy,
        address _sendToken,
        address _receiveToken,
        uint256 _sendQuantity,
        uint256 _minReceiveQuantity
    ) private returns (bool) {
        uint256 reserveBalance = _getTokenOrETHBalance(_strategy, _reserve);
        bool swapped = false;
        uint256 diff = reserveBalance;
        // Going through curve but switching first to reserve
        if (_sendToken != _reserve && _findCurvePool(_reserve, _receiveToken) != address(0)) {
            uint256 sendBalance = _getTokenOrETHBalance(_strategy, _sendToken);
            try
                ITradeIntegration(univ3).trade(
                    _strategy,
                    _sendToken,
                    sendBalance < _sendQuantity ? sendBalance : _sendQuantity, // can be lower than sendQuantity if we tried swapping
                    _reserve,
                    1
                )
            {
                if (_reserve == _receiveToken) {
                    return true;
                }
                diff = _getTokenOrETHBalance(_strategy, _reserve).sub(reserveBalance);
                swapped = true;
            } catch {}
        }
        if (_sendToken == _reserve || swapped) {
            if (_curveSwap(_strategy, _reserve, _receiveToken, diff, _minReceiveQuantity)) {
                return true;
            }
            if (swapped) {
                require(false, 'Curve Swap failed midway'); // Should never happen
            }
        }
        // Going through curve to reserve and then receive Token
        if (_sendToken != _reserve) {
            uint256 sendBalance = _getTokenOrETHBalance(_strategy, _sendToken);
            swapped = false;
            reserveBalance = _getTokenOrETHBalance(_strategy, _reserve);
            if (_curveSwap(_strategy, _sendToken, _reserve, sendBalance < _sendQuantity ? sendBalance : _sendQuantity, 1)) {
                swapped = true;
                diff = _getTokenOrETHBalance(_strategy, _reserve).sub(reserveBalance);
                if (_reserve == _receiveToken) {
                    return true;
                }
            }
        }
        if (_sendToken == _reserve || swapped) {
            try ITradeIntegration(univ3).trade(_strategy, _reserve, diff, _receiveToken, _minReceiveQuantity) {
                return true;
            } catch {
                if (swapped) {
                    // TODO: check that there is uni3 liquidity instead
                    // require(false, 'Uni Swap failed midway');
                    // Revert
                    _curveSwap(_strategy, _reserve, _sendToken, _getTokenOrETHBalance(_strategy, _reserve), 1);
                }
            }
        }
        return false;
    }

    function _findCurvePool(address _fromToken, address _toToken) private view returns (address) {
        ICurveRegistry curveRegistry = ICurveRegistry(curveAddressProvider.get_registry());
        address curvePool = curveRegistry.find_pool_for_coins(_fromToken, _toToken);
        if (curvePool == address(0) && _fromToken == WETH) {
            curvePool = curveRegistry.find_pool_for_coins(ETH_ADD_CURVE, _toToken);
        }
        if (curvePool == address(0) && _toToken == WETH) {
            curvePool = curveRegistry.find_pool_for_coins(_fromToken, ETH_ADD_CURVE);
        }
        return curvePool;
    }

    function _curveSwap(
        address _strategy,
        address _fromToken,
        address _toToken,
        uint256 _sendTokenAmount,
        uint256 _minReceiveQuantity
    ) private returns (bool) {
        address curvePool = _findCurvePool(_fromToken, _toToken);
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
        ISynthetix snx = ISynthetix(ISnxProxy(SNX).target());
        try snx.synths(stringToBytes32(ERC20(_token).symbol())) returns (ISnxSynth _synth) {
            return address(_synth);
        } catch {
            return address(0);
        }
    }

    function stringToBytes32(string memory source) private pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }
        assembly {
            result := mload(add(source, 32))
        }
    }
}
