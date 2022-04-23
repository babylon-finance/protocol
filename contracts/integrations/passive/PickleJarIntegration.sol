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
import {IJar} from '../../interfaces/external/pickle/IJar.sol';
import {IJarUniV3} from '../../interfaces/external/pickle/IJarUniV3.sol';

/**
 * @title PickleJarIntegration
 * @author Babylon Finance Protocol
 *
 * Pickle Jar Integration
 */
contract PickleJarIntegration is PassiveIntegration {
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
    constructor(IBabController _controller, IPickleJarRegistry _pickleJarRegistry) PassiveIntegration('pickle_jar', _controller) {
      pickleRegistry = _pickleJarRegistry;
    }

    /* ============ Internal Functions ============ */
    function _getSpender(
        address _jar,
        uint8 /* _op */
    ) internal pure override returns (address) {
        return _jar;
    }

    function _getExpectedShares(address _jar, uint256 _amount) internal view override returns (uint256) {
        // Normalize to 18 decimals
        uint256 amoountNormalized = SafeDecimalMath.normalizeAmountTokens(IJar(_jar).token(), _jar, _amount);
        return amoountNormalized.preciseDiv(IJar(_jar).getRatio());
    }

    function _getInvestmentAsset(address _jar) internal view override returns (address) {
        if (pickleRegistry(_jar).isUniv3()) {
          return IJarUniV3(_jar).token0();
        } else {
          return IJar(_jar).token();
        }
    }

    function _getResultAsset(address _jar) internal view virtual override returns (address) {
        return _jar;
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
        address token = _getInvestmentAsset(_asset);
        require(token != address(0), 'Pickle jar does not exist');

        if (pickleRegistry(_jar).isUniv3()) {
          if (pickleRegistry(_jar).noSwapParam()) {
            methodData = abi.encodeWithSignature('deposit(uint256,uint256)', _maxAmountIn.div(2), _maxAmountIn.div(2));
          } else {
            methodData = abi.encodeWithSignature('deposit(uint256,uint256,bool)', _maxAmountIn, 0, true);
          }
        } else {
          methodData = abi.encodeWithSignature('deposit(uint256)', _maxAmountIn);
        }
        // Encode method data for Garden to invoke
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
}
