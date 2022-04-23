// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';

import {IBabController} from '../../interfaces/IBabController.sol';
import {IPriceOracle} from '../../interfaces/IPriceOracle.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {PassiveIntegration} from './PassiveIntegration.sol';
import {IHarvestV3Stake} from '../../interfaces/external/harvest/IHarvestV3Stake.sol';

/**
 * @title HarvestV3StakeIntegration
 * @author Babylon Finance Protocol
 *
 * Harvest V3 Stake Integration
 */
contract HarvestV3StakeIntegration is PassiveIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ State Variables ============ */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) PassiveIntegration('harvest_stake_v3', _controller) {}

    /* ============ Internal Functions ============ */
    function _getSpender(
        address _stakingPool,
        uint8 /* _op */
    ) internal pure override returns (address) {
        return _stakingPool;
    }

    function _getExpectedShares(
        address, /* _asset */
        uint256 _amount
    ) internal pure override returns (uint256) {
        return _amount;
    }

    function _getInvestmentAsset(address _asset) internal view override returns (address lptoken) {
        return IHarvestV3Stake(_asset).lpToken();
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
        address lpToken = _getInvestmentAsset(_asset);
        require(lpToken != address(0), 'Harvest V3 Stake pool does not exist');
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSignature('stake(uint256)', _maxAmountIn);
        return (_asset, 0, methodData);
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
        pure
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        // Withdraw all and claim
        bytes memory methodData = abi.encodeWithSignature('withdraw(uint256)', _investmentTokensIn);
        // Go through the reward pool instead of the booster
        return (_asset, 0, methodData);
    }

    /**
     * Return exit investment calldata to execute after exit if any
     *
     * hparam  _strategy                       Address of the reward pool
     * @param  _pool                           Address of the reward pool
     * hparam  _amount                         Amount of tokens
     * @param  _passiveOp                      enter is 0, exit is 1
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getPostActionCallData(
        address /* _strategy */,
        address _pool,
        uint256, /* _amount */
        uint256 _passiveOp
    )
        internal
        pure
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        // Don't do anything on enter
        if (_passiveOp == 0) {
            return (address(0), 0, bytes(''));
        }
        // Withdraw all and claim
        bytes memory methodData = abi.encodeWithSignature('getAllRewards()');
        // Go through the reward pool instead of the booster
        return (_pool, 0, methodData);
    }

    function _getRewards(address _strategy, address _asset)
        internal
        view
        override
        returns (address token, uint256 balance)
    {
        IHarvestV3Stake pool = IHarvestV3Stake(_asset);
        IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
        address reserveAsset = IGarden(IStrategy(_strategy).garden()).reserveAsset();
        uint256 rewardsLength = pool.rewardTokensLength();
        uint256 totalAmount = 0;
        if (rewardsLength > 0) {
            for (uint256 i = 0; i < rewardsLength; i++) {
                uint256 rewardAmount = pool.earned(i, _strategy);
                totalAmount = totalAmount.add(
                    oracle.getPrice(pool.rewardTokens(i), reserveAsset).preciseMul(rewardAmount)
                );
            }
        }
        return (reserveAsset, totalAmount);
    }
}
