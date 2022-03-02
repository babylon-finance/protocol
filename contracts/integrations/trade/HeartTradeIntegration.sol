// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.9;

import {IBabController} from '../../interfaces/IBabController.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IPriceOracle} from '../../interfaces/IPriceOracle.sol';
import {ISwapRouter} from '../../interfaces/external/uniswap-v3/ISwapRouter.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {TradeIntegration} from './TradeIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';

/**
 * @title Heart Trade Integration
 * @author Babylon Finance Protocol
 *
 * Heart trade integration. Heart buys protocol wanted assets
 */
contract HeartTradeIntegration is TradeIntegration {
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    /* ============ Constants ============ */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) TradeIntegration('heart_trade', _controller) {}

    /* ============ Internal Functions ============ */

    /**
     * Executes the trade through the heart.
     *
     * hparam _strategy             Address of the strategy
     * @param _sendToken            Address of the token to be sent to the heart
     * @param _sendQuantity         Units of reserve asset token sent to the heart
     * hparam _receiveToken         Address of the token that will be received from the heart
     */
    function _getTradeCallData(
        address, /* _strategy */
        address _sendToken,
        uint256 _sendQuantity,
        address /* _receiveToken */
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
        bytes memory callData =
            abi.encodeWithSignature('sellWantedAssetToHeart(address,uint256)', _sendToken, _sendQuantity);
        return (controller.heart(), 0, callData);
    }

    /**
     * Returns the address to approve source tokens to for trading. This is the TokenTaker address
     *
     * @return address             Address of the contract to approve tokens to
     */
    function _getSpender(
        address /* _asset */
    ) internal view override returns (address) {
        return address(controller.heart());
    }
}
