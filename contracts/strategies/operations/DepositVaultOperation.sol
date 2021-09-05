/*
    Copyright 2021 Babylon Finance.

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

import 'hardhat/console.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IPassiveIntegration} from '../../interfaces/IPassiveIntegration.sol';

import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';

import {Operation} from './Operation.sol';

/**
 * @title DepositVaultOperation/Stake Operation
 * @author Babylon Finance
 *
 * Executes a stake (deposit vault) operation
 */
contract DepositVaultOperation is Operation {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using BytesLib for bytes;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, address _controller) Operation(_name, _controller) {}

    /**
     * Sets operation data for the deposit vault operation
     *
     * @param _data                   Operation data
     */
    function validateOperation(
        bytes calldata _data,
        IGarden, /* _garden */
        address _integration,
        uint256 /* _index */
    ) external view override onlyStrategy {}

    /**
     * Executes the deposit vault operation
     * @param _asset              Asset to receive into this operation
     * @param _capital            Amount of asset received
     * param _assetStatus         Status of the asset amount
     * @param _data               OpData e.g. Address of the vault to enter
     * param _garden              Garden of the strategy
     * @param _integration        Address of the integration to execute
     */
    function executeOperation(
        address _asset,
        uint256 _capital,
        uint8, /* _assetStatus */
        bytes calldata _data,
        IGarden, /* _garden */
        address _integration
    )
        external
        override
        onlyStrategy
        returns (
            address,
            uint256,
            uint8
        )
    {
        address yieldVault = BytesLib.decodeOpDataAddress(_data);
        address vaultAsset = IPassiveIntegration(_integration).getInvestmentAsset(yieldVault);
        if (vaultAsset != _asset) {
            // get ETH if it's needed
            if (vaultAsset == address(0)) {
                if (_asset != WETH) {
                    IStrategy(msg.sender).trade(_asset, _capital, WETH);
                }
                IStrategy(msg.sender).handleWeth(false, IERC20(WETH).balanceOf(msg.sender));
            } else {
                IStrategy(msg.sender).trade(_asset, _capital, vaultAsset);
            }
        }
        uint256 minAmountExpected = _getMinAmountExpected(yieldVault, _capital, _integration);
        IPassiveIntegration(_integration).enterInvestment(
            msg.sender,
            yieldVault,
            minAmountExpected,
            vaultAsset,
            vaultAsset == address(0) ? address(msg.sender).balance : IERC20(vaultAsset).balanceOf(msg.sender)
        );
        vaultAsset = IPassiveIntegration(_integration).getResultAsset(yieldVault);
        return (vaultAsset, IERC20(vaultAsset).balanceOf(msg.sender), 0); // liquid
    }

    function _getMinAmountExpected(
        address _yieldVault,
        uint256 _capital,
        address _integration
    ) internal view returns (uint256) {
        uint256 exactAmount = IPassiveIntegration(_integration).getExpectedShares(_yieldVault, _capital);
        return exactAmount.sub(exactAmount.preciseMul(SLIPPAGE_ALLOWED));
    }

    /**
     * Exits the deposit vault operation.
     * @param _percentage of capital to exit from the strategy
     */
    function exitOperation(
        address, /* _asset */
        uint256, /* _remaining */
        uint8, /* _assetStatus */
        uint256 _percentage,
        bytes calldata _data,
        IGarden, /* _garden */
        address _integration
    )
        external
        override
        onlyStrategy
        returns (
            address,
            uint256,
            uint8
        )
    {
        address yieldVault = BytesLib.decodeOpDataAddress(_data);
        require(_percentage <= HUNDRED_PERCENT, 'Unwind Percentage <= 100%');
        address vaultAsset = IPassiveIntegration(_integration).getInvestmentAsset(yieldVault);
        uint256 amountVault =
            IERC20(IPassiveIntegration(_integration).getResultAsset(yieldVault)).balanceOf(msg.sender).preciseMul(
                _percentage
            );
        uint256 minAmount =
            IPassiveIntegration(_integration).getPricePerShare(yieldVault).mul(
                amountVault.sub(amountVault.preciseMul(SLIPPAGE_ALLOWED))
            );
        IPassiveIntegration(_integration).exitInvestment(msg.sender, yieldVault, amountVault, vaultAsset, minAmount);
        return (
            vaultAsset,
            vaultAsset != address(0) ? IERC20(vaultAsset).balanceOf(msg.sender) : address(msg.sender).balance,
            0
        );
    }

    /**
     * Gets the NAV of the deposit vault op in the reserve asset
     *
     * @param _data               OpData e.g. Vault
     * @param _garden             Garden the strategy belongs to
     * @param _integration        Status of the asset amount
     * @return _nav               NAV of the strategy
     */
    function getNAV(
        bytes calldata _data,
        IGarden _garden,
        address _integration
    ) external view override returns (uint256, bool) {
        address vault = BytesLib.decodeOpDataAddress(_data); // 64 bytes (w/o signature prefix bytes4)
        if (!IStrategy(msg.sender).isStrategyActive()) {
            return (0, true);
        }
        address vaultAsset = IPassiveIntegration(_integration).getResultAsset(vault);
        uint256 balance = IERC20(vaultAsset).balanceOf(msg.sender);
        uint256 price = _getPrice(_garden.reserveAsset(), vaultAsset);
        // If we cannot price the result asset, we'll use the investment one as a floor
        if (price == 0) {
            vaultAsset = IPassiveIntegration(_integration).getInvestmentAsset(vault);
            price = _getPrice(_garden.reserveAsset(), vaultAsset);
        }
        uint256 pricePerShare = IPassiveIntegration(_integration).getPricePerShare(vault);
        // Normalization of pricePerShare
        pricePerShare = pricePerShare.mul(
            10**PreciseUnitMath.decimals().sub(vaultAsset == address(0) ? 18 : ERC20(vaultAsset).decimals())
        );
        //Balance normalization
        balance = SafeDecimalMath.normalizeAmountTokens(vaultAsset, _garden.reserveAsset(), balance);
        uint256 NAV = pricePerShare.preciseMul(balance).preciseDiv(price);
        require(NAV != 0, 'NAV has to be bigger 0');
        return (NAV, true);
    }
}
