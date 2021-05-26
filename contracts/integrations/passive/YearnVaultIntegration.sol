/*
    Copyright 2021 Babylon Finance

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.7.6;
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {PassiveIntegration} from './PassiveIntegration.sol';
import {YRegistry} from '../../interfaces/external/yearn/YRegistry.sol';
import {IVault} from '../../interfaces/external/yearn/IVault.sol';

/**
 * @title YearnIntegration
 * @author Babylon Finance Protocol
 *
 * Yearn v2 Vault Integration
 */
contract YearnVaultIntegration is PassiveIntegration {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;

    /* ============ State Variables ============ */

    // Address of Kyber Network Proxy
    YRegistry public yearnv2Registry;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     * @param _weth                         Address of the WETH ERC20
     * @param _yearnRegistryAddress           Address of Balancer core factory address
     */
    constructor(
        address _controller,
        address _weth,
        address _yearnRegistryAddress
    ) PassiveIntegration('yearnvaults', _weth, _controller) {
        yearnv2Registry = YRegistry(_yearnRegistryAddress);
    }

    /* ============ Internal Functions ============ */

    function _isInvestment(address _investmentAddress) internal view override returns (bool) {
        (address _controller, , , , ) = yearnv2Registry.getVaultInfo(_investmentAddress);
        return _controller != address(0);
    }

    function _getSpender(address _investmentAddress) internal pure override returns (address) {
        return _investmentAddress;
    }

    function _getExpectedShares(address _investmentAddress, uint256 _amount)
        internal
        view
        override
        returns (uint256)
    {
        return _amount.preciseDiv(IVault(_investmentAddress).getPricePerFullShare());
    }

    function _getPricePerShare(address _investmentAddress) internal view override returns (uint256) {
        return IVault(_investmentAddress).getPricePerFullShare();
    }

    function _getInvestmentAsset(address _investmentAddress) internal view override returns (address) {
        return IVault(_investmentAddress).token();
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
        bytes memory methodData = abi.encodeWithSignature('deposit(uint256)', _maxAmountIn);

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
        bytes memory methodData = abi.encodeWithSignature('withdraw(uint256)', _investmentTokensIn);

        return (_investmentAddress, 0, methodData);
    }
}
