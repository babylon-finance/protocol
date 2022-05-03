// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
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
        // Encode method data for Garden to invoke
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
        bytes memory methodData = abi.encodeWithSignature('withdraw(uint256)', _investmentTokensIn);
        // Go through the reward pool instead of the booster
        return (gauge, 0, methodData);
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
        if (_passiveOp == 1) {
            // Claim rewards
            address gauge = curveMetaRegistry.getGauge(_asset);
            try IGauge(gauge).last_claim() returns (uint256) {
                // only do it for v3 gauges
                bytes memory methodData =
                    abi.encodeWithSignature('claim_rewards(address,address)', _strategy, _strategy);
                return (gauge, 0, methodData);
            } catch {}
        }
        return (address(0), 0, bytes(''));
    }

    function _getRewards(address _strategy, address _asset)
        internal
        view
        override
        returns (address token, uint256 balance)
    {
        IGauge gauge = IGauge(curveMetaRegistry.getGauge(_asset));
        IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
        uint256 totalAmount = 0;
        uint256 extraRewardsLength = 8; // max of 8 tokens in curve
        try gauge.last_claim() returns (uint256) {
            for (uint256 i = 0; i < extraRewardsLength; i++) {
                address rewardToken = gauge.rewarded_tokens(i);
                uint256 claimable = gauge.claimable_reward_write(_strategy, rewardToken);
                if (claimable > 0) {
                    claimable = claimable.sub(gauge.claimed_reward(_strategy, rewardToken));
                    if (claimable > 0) {
                        try oracle.getPrice(rewardToken, WETH) returns (uint256 priceExtraReward) {
                            totalAmount = totalAmount.add(priceExtraReward.preciseMul(claimable));
                        } catch {}
                    }
                }
            }
        } catch {}
        return (WETH, totalAmount);
    }
}
