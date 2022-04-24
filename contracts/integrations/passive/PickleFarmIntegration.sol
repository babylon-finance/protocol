// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import 'hardhat/console.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';

import {IBabController} from '../../interfaces/IBabController.sol';
import {IPriceOracle} from '../../interfaces/IPriceOracle.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IPickleJarRegistry} from '../../interfaces/IPickleJarRegistry.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {PassiveIntegration} from './PassiveIntegration.sol';
import {IJar} from '../../interfaces/external/pickle/IJar.sol';
import {IJarUniV3} from '../../interfaces/external/pickle/IJarUniV3.sol';

/**
 * @title PickleFarmIntegration
 * @author Babylon Finance Protocol
 *
 * Pickle Farm Integration
 */
contract PickleFarmIntegration is PassiveIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ State Variables ============ */
    IPickleJarRegistry public immutable pickleRegistry;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     * @param _pickleJarRegistry            Address of our pickle jar registry
     */
    constructor(IBabController _controller, IPickleJarRegistry _pickleJarRegistry)
        PassiveIntegration('pickle_farm', _controller)
    {
        pickleRegistry = _pickleJarRegistry;
    }

    /* ============ Internal Functions ============ */
    function _getSpender(
        address _jar,
        uint8 /* _op */
    ) internal view override returns (address) {
        return pickleRegistry.getJarGauge(_jar);
    }

    function _getInvestmentAsset(address _jar) internal pure override returns (address) {
        return _jar;
    }

    function _getResultAsset(address _jar) internal view override returns (address) {
        return pickleRegistry.getJarGauge(_jar);
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
        address /* _strategy */,
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
        require(pickleRegistry.jars(_asset), 'Pickle jar does not exist');
        address gauge = pickleRegistry.getJarGauge(_asset);
        require(gauge != address(0), 'Gauge does not exist');
        bytes memory methodData = abi.encodeWithSignature('deposit(uint256)', _maxAmountIn);
        // Encode method data for Garden to invoke
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
        address gauge = pickleRegistry.getJarGauge(_asset);
        // Withdraw
        bytes memory methodData = abi.encodeWithSignature('withdraw(uint256)', _investmentTokensIn);
        // Go through the reward pool instead of the booster
        return (gauge, 0, methodData);
    }
}
