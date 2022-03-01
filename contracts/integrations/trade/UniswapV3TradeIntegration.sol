// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.9;
pragma abicoder v2;

import {IBabController} from '../../interfaces/IBabController.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IPriceOracle} from '../../interfaces/IPriceOracle.sol';
import {ISwapRouter} from '../../interfaces/external/uniswap-v3/ISwapRouter.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {TradeIntegration} from './TradeIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';

/**
 * @title UniswapV3TradeIntegration
 * @author Babylon Finance Protocol
 *
 * UniswapV3 trade integration
 */
contract UniswapV3TradeIntegration is TradeIntegration {
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

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
    constructor(IBabController _controller) TradeIntegration('univ3_3', _controller) {}

    /* ============ Internal Functions ============ */

    /**
     * Executes the trade through UniswapV3.
     *
     * @param _strategy             Address of the strategy
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of reserve asset token sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     * @param _hopToken             Address of the routing token for multi-hop, i.e., sendToken->hopToken->receiveToken
     */
    function _getTradeCallData(
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        address _hopToken
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
        if (_hopToken == address(0) || _sendToken == _hopToken || _receiveToken == _hopToken) {
            (, uint24 fee) = _getUniswapPoolWithHighestLiquidity(_sendToken, _receiveToken);
            path = abi.encodePacked(_sendToken, fee, _receiveToken);
        } else {
            (, uint24 fee0) = _getUniswapPoolWithHighestLiquidity(_sendToken, _hopToken);
            (, uint24 fee1) = _getUniswapPoolWithHighestLiquidity(_receiveToken, _hopToken);
            path = abi.encodePacked(_sendToken, fee0, _hopToken, fee1, _receiveToken);
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
        return _getTradeCallData(_strategy, _sendToken, _sendQuantity, _receiveToken, WETH);
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

    /* ============ Private Functions ============ */

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
