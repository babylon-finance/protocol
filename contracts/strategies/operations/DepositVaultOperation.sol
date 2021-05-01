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

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {Operation} from './Operation.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {IPassiveIntegration} from '../../interfaces/IPassiveIntegration.sol';

/**
 * @title DepositVaultOperation
 * @author Babylon Finance
 *
 * Executes a deposit vault operation
 */
contract DepositVaultOperation is Operation {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;

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
        bytes32 _data,
        IGarden _garden,
        IStrategy _strategy,
        address _integration
    ) external view override onlyStrategy {
        require(IPassiveIntegration(_integration).isInvestment(getParsedData(_data)), 'Must be a valid yield vault');
    }

    /**
     * Executes the deposit vault operation
     * @param _capital      Amount of capital received from the garden
     */
    function executeOperation(
        address _asset,
        uint256 _capital,
        bytes32 _data,
        IGarden _garden,
        IStrategy _strategy,
        address _integration
    ) external override onlyStrategy returns (address, uint256) {
        address yieldVault = getParsedData(_data);
        address vaultAsset = IPassiveIntegration(_integration).getInvestmentAsset(yieldVault);
        if (vaultAsset != _asset) {
            IStrategy(_strategy).trade(_asset, _capital, vaultAsset);
        }
        uint256 exactAmount = IPassiveIntegration(_integration).getExpectedShares(yieldVault, _capital);
        uint256 minAmountExpected = exactAmount.sub(exactAmount.preciseMul(SLIPPAGE_ALLOWED));
        IPassiveIntegration(_integration).enterInvestment(
            yieldVault,
            minAmountExpected,
            vaultAsset,
            IERC20(vaultAsset).balanceOf(msg.sender)
        );
        return (yieldVault, IERC20(yieldVault).balanceOf(msg.sender));
    }

    /**
     * Exits the deposit vault operation.
     * @param _percentage of capital to exit from the strategy
     */
    function exitOperation(
        uint256 _percentage,
        bytes32 _data,
        IGarden _garden,
        IStrategy _strategy,
        address _integration
    ) external override onlyStrategy {
        require(_percentage <= HUNDRED_PERCENT, 'Unwind Percentage <= 100%');
        address yieldVault = getParsedData(_data);
        address vaultAsset = IPassiveIntegration(_integration).getInvestmentAsset(yieldVault);
        uint256 amountVault = IERC20(yieldVault).balanceOf(msg.sender).preciseMul(_percentage);
        IPassiveIntegration(_integration).exitInvestment(
            yieldVault,
            amountVault,
            vaultAsset,
            IPassiveIntegration(_integration).getPricePerShare(yieldVault).mul(
                amountVault.sub(amountVault.preciseMul(SLIPPAGE_ALLOWED))
            )
        );
        if (vaultAsset != _garden.reserveAsset()) {
            IStrategy(_strategy).trade(vaultAsset, IERC20(vaultAsset).balanceOf(msg.sender), _garden.reserveAsset());
        }
    }

    /**
     * Gets the NAV of the deposit vault op in the reserve asset
     *
     * @return _nav           NAV of the strategy
     */
    function getNAV(
        bytes32 _data,
        IGarden _garden,
        IStrategy _strategy,
        address _integration
    ) external view override onlyStrategy returns (uint256) {
        if (!_strategy.isStrategyActive()) {
            return 0;
        }
        address yieldVault = getParsedData(_data);
        address vaultAsset = IPassiveIntegration(_integration).getInvestmentAsset(yieldVault);
        uint256 price = _getPrice(_garden.reserveAsset(), vaultAsset);
        uint256 NAV =
            IPassiveIntegration(_integration)
                .getPricePerShare(yieldVault)
                .mul(IERC20(yieldVault).balanceOf(msg.sender))
                .div(price);
        require(NAV != 0, 'NAV has to be bigger 0');
        return NAV;
    }

    /* ============ Private Functions ============ */

    function getParsedData(bytes32 _data) private view returns (address) {
        return _convertDataToAddress(_data);
    }
}
