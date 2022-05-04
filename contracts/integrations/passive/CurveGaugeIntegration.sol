// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {IPriceOracle} from '../../interfaces/IPriceOracle.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {PassiveIntegration} from './PassiveIntegration.sol';
import {IGauge} from '../../interfaces/external/curve/IGauge.sol';
import {ICurveMetaRegistry} from '../../interfaces/ICurveMetaRegistry.sol';

/**
 * @title CurveGaugeIntegration
 * @author Babylon Finance Protocol
 *
 * Curve Gauge Integration
 */
contract CurveGaugeIntegration is PassiveIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ State variables ============ */

    ICurveMetaRegistry public immutable curveMetaRegistry;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller, ICurveMetaRegistry _curveMetaRegistry)
        PassiveIntegration('curve_gauge', _controller)
    {
        curveMetaRegistry = _curveMetaRegistry;
    }

    /* ============ Internal Functions ============ */

    function _getSpender(
        address _asset,
        uint8 /* _op */
    ) internal view override returns (address) {
        return curveMetaRegistry.getGauge(_asset);
    }

    function _getInvestmentAsset(address _asset) internal view override returns (address) {
        return curveMetaRegistry.getLpToken(_asset);
    }

    function _getResultAsset(address _asset) internal view override returns (address) {
        return curveMetaRegistry.getGauge(_asset);
    }

    /**
     * Return join investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * @param  _asset                          Address of the vault
     * hparam  _investmentTokensOut            Amount of investment tokens to send
     * hparam  _tokenIn                        Addresses of tokens to send to the investment
     * @param  _maxAmountIn                    Amounts of tokens to send to the investment
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getEnterInvestmentCalldata(
        address _strategy,
        address _asset,
        uint256, /* _investmentTokensOut */
        address, /* _tokenIn */
        uint256 _maxAmountIn
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
        address gauge = curveMetaRegistry.getGauge(_asset);
        require(gauge != address(0), 'Curve gauge does not exist');
        // Encode method data for Strategy to invoke
        bytes memory methodData = abi.encodeWithSignature('deposit(uint256,address)', _maxAmountIn, _strategy);
        return (gauge, 0, methodData);
    }

    /**
     * Return exit investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * hparam  _asset                          Address of the investment
     * hparam  _investmentTokensIn             Amount of investment tokens to receive
     * hparam  _tokenOut                       Addresses of tokens to receive
     * hparam  _minAmountOut                   Amounts of investment tokens to receive
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getExitInvestmentCalldata(
        address, /* _strategy */
        address _asset,
        uint256 _investmentTokensIn,
        address, /* _tokenOut */
        uint256 /* _minAmountOut */
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
        address gauge = curveMetaRegistry.getGauge(_asset);
        require(gauge != address(0), 'Curve gauge does not exist');
        // Withdraw all and claim
        // Check if the gauge is LiquidityGaugeV3
        try IGauge(gauge).last_claim() returns (uint256) {
            bytes memory methodData = abi.encodeWithSignature('withdraw(uint256,bool)', _investmentTokensIn, true);
            return (gauge, 0, methodData);
        } catch {
            bytes memory methodData = abi.encodeWithSignature('withdraw(uint256)', _investmentTokensIn);
            return (gauge, 0, methodData);
        }
    }

    /**
     * Return post action calldata
     *
     * hparam  _asset                    Address of the asset to deposit
     * hparam  _amount                   Amount of the token to deposit
     * hparam  _passiveOp                Type of op
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPostActionCallData(
        address _strategy,
        address _asset,
        uint256, /* _amount */
        uint256 _passiveOp
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
        return (address(0), 0, bytes(''));
    }

    function _getRewards(address _strategy, address _asset)
        internal
        view
        override
        returns (address token, uint256 balance)
    {
        IGauge gauge = IGauge(curveMetaRegistry.getGauge(_asset));
        // Will fai for LiquidityGaugeV1, but work for LiquidityGaugeV2/V3
        address token = gauge.reward_tokens(0);
        return (token, token != address(0) ? IERC20(token).balanceOf(_strategy) : 0);
    }
}
