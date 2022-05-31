// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {IPriceOracle} from '../../interfaces/IPriceOracle.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {PassiveIntegration} from './PassiveIntegration.sol';
import {IRibbonVault} from '../../interfaces/external/ribbon/IRibbonVault.sol';
import {IGaugeController} from '../../interfaces/external/ribbon/IGaugeController.sol';
import {IGauge} from '../../interfaces/external/curve/IGauge.sol';

/**
 * @title RibbonIntegration
 * @author Babylon Finance Protocol
 *
 * Ribbon Integration
 */
contract RibbonIntegration is PassiveIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ Constants ============ */
    address private constant RBN = 0x6123B0049F904d730dB3C36a31167D9d4121fA6B;
    IGaugeController private constant gaugeController = IGaugeController(0x0cb9cc35cEFa5622E8d25aF36dD56DE142eF6415);
    /* ============ State Variables ============ */
    mapping(address => bool) public signal;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) PassiveIntegration('ribbon_vault', _controller) {}

    /* ============ Public Functions ============ */

    /* ============ Internal Functions ============ */

    function _getSpender(
        address _vault,
        uint8 /* _op */
    ) internal pure override returns (address) {
        return _vault;
    }

    function _getInvestmentAsset(address _vault) internal view override returns (address) {
        return IRibbonVault(_vault).vaultParams().asset;
    }

    function _getResultAsset(address _vault) internal view override returns (address) {
        return IRibbonVault(_vault).liquidityGauge();
    }

    function _getResultBalance(address _strategy, address _resultAssetAddress)
        internal
        view
        override
        returns (uint256)
    {
        ERC20 gauge = ERC20(IRibbonVault(_resultAssetAddress).liquidityGauge());
        return gauge.balanceOf(_strategy);
    }

    function _getRewards(address _strategy, address _vault) internal view override returns (address, uint256) {
        IGauge gauge = IGauge(IRibbonVault(_vault).liquidityGauge());
        uint256 rewards = gauge.claimable_reward(_strategy, RBN);
        return (address(RBN), rewards);
    }

    /**
     * Return join investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * @param  _asset                          Address of the vault
     * hparam  _investmentTokensOut            Amount of investment tokens to send
     * hparam  _tokenIn                        Addresses of tokens to send to the investment
     * hparam  _maxAmountIn                    Amounts of tokens to send to the investment
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
        require(_isValid(_asset), 'Ribbon Vault is not valid');
        bytes memory methodData = abi.encodeWithSignature('deposit(uint256)', _maxAmountIn);
        return (_asset, 0, methodData);
    }

    /**
     * Return exit investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * @param  _asset                          Address of the investment
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
        uint256, /* _investmentTokensIn */
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
        require(_isValid(_asset), 'Ribbon Vault is not valid');
        bytes memory methodData = abi.encodeWithSignature('completeWithdraw()');
        return (_asset, 0, methodData);
    }

    /**
     * Return post action calldata
     *
     * hparam  _strategy                 Address of the strategy
     * @param  _asset                    Address of the asset to deposit
     * hparam  _amount                   Amount of the token to deposit
     * @param  _passiveOp                Type of op
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPostActionCallData(
        address, /* _strategy */
        address _asset,
        uint256 _amount,
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
        if (_passiveOp == 0) {
            // Stake
            bytes memory methodData = abi.encodeWithSignature('stake(uint256)', _amount);
            return (_asset, 0, methodData);
        }
        return (address(0), 0, bytes(''));
    }

    /**
     * Return unlock investment calldata to prepare for withdrawal
     *
     * hparam  _strategy                       Address of the strategy
     * hparam  _data                           Data
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getUnlockInvestmentCalldata(address _strategy, bytes calldata _data)
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        address _vault = BytesLib.decodeOpDataAddress(_data);
        address gauge = IRibbonVault(_vault).liquidityGauge();
        // Unstake
        uint256 balance = ERC20(gauge).balanceOf(_strategy);
        if (balance > 0) {
            bytes memory methodData = abi.encodeWithSignature('withdraw(uint256,bool)', balance, true);
            return (gauge, 0, methodData);
        }
        // If unstake initiate withdrawal
        bytes memory methodData =
            abi.encodeWithSignature('initiateWithdraw(uint256)', IRibbonVault(_vault).shares(_strategy));
        // Flag as true
        // signal[_strategy] = true;
        return (_vault, 0, methodData);
    }

    /**
     * Checks if the integration needs to execute a tx to prepare the withdrawal
     *
     * @param _strategy                           Address of the strategy
     * hparam _data                               Data param
     * @return bool                               True if it is needed
     */
    function _needsUnlockSignal(address _strategy, bytes calldata _data) internal view override returns (bool) {
        address _asset = BytesLib.decodeOpDataAddress(_data);
        ERC20 gauge = ERC20(IRibbonVault(_asset).liquidityGauge());
        return
            gauge.balanceOf(_strategy) > 0 ||
            (_getRemainingDurationStrategy(_strategy) <= (7 days) && !signal[_strategy]);
    }

    /**
     * Checks if a vault is valid
     *
     * @param _vault                           Address of the vault
     * @return bool                            True if it is valid
     */
    function _isValid(address _vault) internal view returns (bool) {
        address gauge = IRibbonVault(_vault).liquidityGauge();
        return gaugeController.gauge_types(gauge) >= 0;
    }
}
