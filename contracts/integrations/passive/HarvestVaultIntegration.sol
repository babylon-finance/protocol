// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.9;
pragma abicoder v1;
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';

import {IBabController} from '../../interfaces/IBabController.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {PassiveIntegration} from './PassiveIntegration.sol';

import {IHarvestVault} from '../../interfaces/external/harvest/IVault.sol';

/**
 * @title HarvestIntegration
 * @author Babylon Finance Protocol
 *
 * Harvest v2 Vault Integration
 */
contract HarvestVaultIntegration is PassiveIntegration {
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) PassiveIntegration('harvestvaults', _controller) {}

    /* ============ External Functions ============ */

    /* ============ Internal Functions ============ */

    function _getSpender(
        address _vault,
        uint8 /* _op */
    ) internal pure override returns (address) {
        return _vault;
    }

    function _getExpectedShares(address _vault, uint256 _amount) internal view override returns (uint256) {
        // Normalizing pricePerShare returned by Harvest
        return
            _amount.preciseDiv(IHarvestVault(_vault).getPricePerFullShare()) /
            (10**PreciseUnitMath.decimals() - (ERC20(_vault).decimals()));
    }

    function _getPricePerShare(address _vault) internal view override returns (uint256) {
        return IHarvestVault(_vault).getPricePerFullShare();
    }

    function _getInvestmentAsset(address _vault) internal view override returns (address) {
        return IHarvestVault(_vault).underlying();
    }

    /**
     * Return join investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * @param  _investmentAddress              Address of the vault
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
        address _investmentAddress,
        uint256, /* _investmentTokensOut */
        address, /* _tokenIn */
        uint256 _maxAmountIn
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
        bytes memory methodData = abi.encodeWithSelector(IHarvestVault.deposit.selector, _maxAmountIn);

        return (_investmentAddress, 0, methodData);
    }

    /**
     * Return exit investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * @param  _investmentAddress              Address of the investment
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
        address _investmentAddress,
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
        bytes memory methodData = abi.encodeWithSelector(IHarvestVault.withdraw.selector, _investmentTokensIn);

        return (_investmentAddress, 0, methodData);
    }
}
