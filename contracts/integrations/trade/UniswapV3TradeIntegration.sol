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
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IPriceOracle} from '../../interfaces/IPriceOracle.sol';
import {ISwapRouter} from '../../interfaces/external/uniswap-v3/ISwapRouter.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';
import {TradeIntegration} from './TradeIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';

/**
 * @title UniswapV3TradeIntegration
 * @author Babylon Finance Protocol
 *
 * UniswapV3 trade integration
 */
contract UniswapV3TradeIntegration is TradeIntegration {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    /* ============ Constants ============ */
    // Address of Uniswap V3 SwapRouter contract
    address private constant swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) TradeIntegration('univ3_2', _controller) {}

    /* ============ Internal Functions ============ */

    /**
     * Executes the trade through UniswapV3.
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
        bytes memory path;
        if (_sendToken == WETH || _receiveToken == WETH) {
            (, uint24 fee) = _getUniswapPoolWithHighestLiquidity(_sendToken, _receiveToken);
            path = abi.encodePacked(_sendToken, fee, _receiveToken);
        } else {
            (, uint24 fee0) = _getUniswapPoolWithHighestLiquidity(_sendToken, WETH);
            (, uint24 fee1) = _getUniswapPoolWithHighestLiquidity(_sendToken, WETH);
            path = abi.encodePacked(_sendToken, fee0, WETH, fee1, _receiveToken);
        }
        ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams(
                path,
                _strategy,
                block.timestamp,
                _sendQuantity,
                1 // we check for amountOutMinimum in the post trade check
            );

        bytes memory callData = abi.encodeWithSignature('exactInput((bytes,address,uint256,uint256,uint256))', params);
        return (swapRouter, 0, callData);
    }

    /**
     * Returns the address to approve source tokens to for trading. This is the TokenTaker address
     *
     * @return address             Address of the contract to approve tokens to
     */
    function _getSpender(
        address /* _swapTarget */
    ) internal pure override returns (address) {
        return address(swapRouter);
    }

    /**
     * Checks liquidity of the trade
     *
     * @param _tradeInfo            Struct containing trade information used in internal functions
     * hparam _sendQuantity         Units of token sent
     */
    function _checkLiquidity(
        TradeInfo memory _tradeInfo,
        uint256 /* _sendQuantity */
    ) internal view override returns (bool) {
        address reserveAsset = _tradeInfo.garden.reserveAsset();
        uint256 liquidityInReserve = _getUniswapHighestLiquidity(_tradeInfo, reserveAsset);
        uint256 minLiquidityReserveAsset = _tradeInfo.garden.minLiquidityAsset();
        console.log('require liquidityInReserve >= minLiquidityReserveAsset', liquidityInReserve >= minLiquidityReserveAsset );
        return liquidityInReserve >= minLiquidityReserveAsset;
    }

    /* ============ Private Functions ============ */

    function _getUniswapHighestLiquidity(TradeInfo memory _tradeInfo, address _reserveAsset)
        private
        view
        returns (uint256)
    {
        address sendToken = _tradeInfo.sendToken;
        address receiveToken = _tradeInfo.receiveToken;
        // Exit if going to same asset
        if (sendToken == receiveToken) {
            return _tradeInfo.garden.minLiquidityAsset();
        }
        (IUniswapV3Pool pool, ) = _getUniswapPoolWithHighestLiquidity(sendToken, receiveToken);
        if (address(pool) == address(0)) {
            console.log('POOL ZERO ADDRESS');
            return 0;
        }
        uint256 poolLiquidity = uint256(pool.liquidity());
        uint256 liquidityInReserve;
        address denominator;

        if (pool.token0() == DAI || pool.token0() == WETH || pool.token0() == USDC || pool.token0() == WBTC) {
            liquidityInReserve = poolLiquidity.mul(poolLiquidity).div(ERC20(pool.token1()).balanceOf(address(pool)));
            denominator = pool.token0();
        } else {
            liquidityInReserve = poolLiquidity.mul(poolLiquidity).div(ERC20(pool.token0()).balanceOf(address(pool)));
            denominator = pool.token1();
        }
        // Normalize to reserve asset
        if (denominator != _reserveAsset) {
            IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
            uint256 price = oracle.getPrice(denominator, _reserveAsset);
            liquidityInReserve = liquidityInReserve.preciseMul(price);
        }
        return liquidityInReserve;
    }

    function _getUniswapPoolWithHighestLiquidity(address sendToken, address receiveToken)
        private
        view
        returns (IUniswapV3Pool pool, uint24 fee)
    {
        IUniswapV3Pool poolLow = IUniswapV3Pool(uniswapFactory.getPool(sendToken, receiveToken, FEE_LOW));
        IUniswapV3Pool poolMedium = IUniswapV3Pool(uniswapFactory.getPool(sendToken, receiveToken, FEE_MEDIUM));
        IUniswapV3Pool poolHigh = IUniswapV3Pool(uniswapFactory.getPool(sendToken, receiveToken, FEE_HIGH));

        uint128 liquidityLow = address(poolLow) != address(0) ? poolLow.liquidity() : 0;
        uint128 liquidityMedium = address(poolMedium) != address(0) ? poolMedium.liquidity() : 0;
        uint128 liquidityHigh = address(poolHigh) != address(0) ? poolHigh.liquidity() : 0;
        if (liquidityLow > liquidityMedium && liquidityLow >= liquidityHigh) {
            return (poolLow, FEE_LOW);
        }
        if (liquidityMedium > liquidityLow && liquidityMedium >= liquidityHigh) {
            return (poolMedium, FEE_MEDIUM);
        }
        return (poolHigh, FEE_HIGH);
    }

    function _getReserveAsWeth(address _token, address _reserveAsset) internal pure returns (address) {
        return _reserveAsset == _token ? WETH : _token;
    }
}
