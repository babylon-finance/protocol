// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {IPriceOracle} from '../../interfaces/IPriceOracle.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {PassiveIntegration} from './PassiveIntegration.sol';
import {IBasicRewards} from '../../interfaces/external/convex/IBasicRewards.sol';
import {IConvexRegistry} from '../../interfaces/IConvexRegistry.sol';

/**
 * @title ConvexStakeIntegration
 * @author Babylon Finance Protocol
 *
 * Lido Integration
 */
contract ConvexStakeIntegration is PassiveIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ State variables ============ */

    IConvexRegistry public immutable convexRegistry;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller, IConvexRegistry _convexRegistry)
        PassiveIntegration('convex_v2', _controller)
    {
        convexRegistry = _convexRegistry;
    }

    /* ============ Internal Functions ============ */

    function _getSpender(address _asset, uint8 _op) internal view override returns (address) {
        if (_op == 0) {
            return address(convexRegistry.booster());
        }
        // Reward pool
        return convexRegistry.getRewardPool(_asset);
    }

    function _getExpectedShares(
        address, /* _asset */
        uint256 _amount
    ) internal pure override returns (uint256) {
        return _amount;
    }

    function _getPricePerShare(
        address /* _asset */
    ) internal pure override returns (uint256) {
        return 1e18;
    }

    function _getInvestmentAsset(address _asset) internal view override returns (address lptoken) {
        return convexRegistry.getConvexInputToken(_asset);
    }

    function _getResultAsset(address _investment) internal view virtual override returns (address) {
        return _investment;
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
        address, /* _strategy */
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
        (bool found, uint256 pid) = convexRegistry.getPid(_asset);
        require(found, 'Convex pool does not exist');
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSignature('deposit(uint256,uint256,bool)', pid, _maxAmountIn, true);
        return (address(convexRegistry.booster()), 0, methodData);
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
        // Withdraw all and claim
        bytes memory methodData = abi.encodeWithSignature('withdrawAndUnwrap(uint256,bool)', _investmentTokensIn, true);
        // Go through the reward pool instead of the booster
        return (convexRegistry.getRewardPool(_asset), 0, methodData);
    }

    function _getRewards(address _strategy, address _asset)
        internal
        view
        override
        returns (address token, uint256 balance)
    {
        IBasicRewards rewards = IBasicRewards(convexRegistry.getRewardPool(_asset));
        IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
        uint256 totalAmount = rewards.earned(_strategy).mul(2); // * 2 accounts roughly for CVX
        // add extra rewards and convert to reward token
        uint256 extraRewardsLength = rewards.extraRewardsLength();
        if (extraRewardsLength > 0) {
            for (uint256 i = 0; i < extraRewardsLength; i++) {
                IBasicRewards extraRewards = IBasicRewards(rewards.extraRewards(i));
                uint256 extraAmount = extraRewards.earned(_strategy);
                if (extraAmount > 0) {
                    try oracle.getPrice(rewards.extraRewards(i), extraRewards.rewardToken()) returns (
                        uint256 priceExtraReward
                    ) {
                        totalAmount = totalAmount.add(priceExtraReward.preciseMul(extraAmount));
                    } catch {}
                }
            }
        }
        return (rewards.rewardToken(), totalAmount);
    }
}
