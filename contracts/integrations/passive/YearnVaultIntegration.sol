// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';

import {IBabController} from '../../interfaces/IBabController.sol';
import {IYearnVaultRegistry} from '../../interfaces/IYearnVaultRegistry.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {PassiveIntegration} from './PassiveIntegration.sol';
import {IYearnVault} from '../../interfaces/external/yearn/IYearnVault.sol';

/**
 * @title YearnIntegration
 * @author Babylon Finance Protocol
 *
 * Yearn v2 Vault Integration
 */
contract YearnVaultIntegration is PassiveIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ State Variables ============ */

    IYearnVaultRegistry private immutable yearnVaultRegistry;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller, IYearnVaultRegistry _yearnVaultRegistry)
        PassiveIntegration('yearnvaultsv2', _controller)
    {
        yearnVaultRegistry = _yearnVaultRegistry;
    }

    /* ============ Internal Functions ============ */

    function _getSpender(
        address _asset,
        uint8 /* _op */
    ) internal pure override returns (address) {
        return _asset;
    }

    function _getInvestmentAsset(address _asset) internal view override returns (address) {
        return IYearnVault(_asset).token();
    }

    /**
     * Return join investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * @param  _asset              Address of the vault
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
        require(yearnVaultRegistry.vaults(_asset), 'Yearn vault is not valid');
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSelector(IYearnVault.deposit.selector, _maxAmountIn);

        return (_asset, 0, methodData);
    }

    /**
     * Return exit investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * @param  _asset              Address of the investment
     * @param  _investmentTokensIn             Amount of investment tokens to receive
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
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSelector(IYearnVault.withdraw.selector, _investmentTokensIn);

        return (_asset, 0, methodData);
    }
}
