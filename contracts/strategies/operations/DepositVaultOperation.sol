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
        address _data,
        IGarden, /* _garden */
        address _integration,
        uint256 /* _index */
    ) external view override onlyStrategy {
        require(IPassiveIntegration(_integration).isInvestment(_data), 'Must be a valid yield vault');
    }

    /**
     * Executes the deposit vault operation
     * @param _asset              Asset to receive into this operation
     * @param _capital            Amount of asset received
     * param _assetStatus         Status of the asset amount
     * @param _data               Address of the vault to enter
     * param _garden              Garden of the strategy
     * @param _integration        Address of the integration to execute
     */
    function executeOperation(
        address _asset,
        uint256 _capital,
        uint8, /* _assetStatus */
        address _data,
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
        address yieldVault = _data;
        address vaultAsset = IPassiveIntegration(_integration).getInvestmentAsset(yieldVault);
        if (vaultAsset != _asset) {
            IStrategy(msg.sender).trade(_asset, _capital, vaultAsset);
        }
        uint256 exactAmount = IPassiveIntegration(_integration).getExpectedShares(yieldVault, _capital);
        uint256 minAmountExpected = exactAmount.sub(exactAmount.preciseMul(SLIPPAGE_ALLOWED));
        IPassiveIntegration(_integration).enterInvestment(
            msg.sender,
            yieldVault,
            minAmountExpected,
            vaultAsset,
            IERC20(vaultAsset).balanceOf(msg.sender)
        );
        return (yieldVault, IERC20(yieldVault).balanceOf(msg.sender), 0); // liquid
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
        address _yieldVault,
        IGarden _garden,
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
        require(_percentage <= HUNDRED_PERCENT, 'Unwind Percentage <= 100%');
        address vaultAsset = IPassiveIntegration(_integration).getInvestmentAsset(_yieldVault);
        uint256 amountVault = IERC20(_yieldVault).balanceOf(msg.sender).preciseMul(_percentage);
        uint256 minAmount =
            IPassiveIntegration(_integration).getPricePerShare(_yieldVault).mul(
                amountVault.sub(amountVault.preciseMul(SLIPPAGE_ALLOWED))
            );
        IPassiveIntegration(_integration).exitInvestment(msg.sender, _yieldVault, amountVault, vaultAsset, minAmount);
        if (vaultAsset != _garden.reserveAsset()) {
            IStrategy(msg.sender).trade(vaultAsset, IERC20(vaultAsset).balanceOf(msg.sender), _garden.reserveAsset());
        }
        return (_yieldVault, 0, 0);
    }

    /**
     * Gets the NAV of the deposit vault op in the reserve asset
     *
     * @param _data               Pool
     * @param _garden             Garden the strategy belongs to
     * @param _integration        Status of the asset amount
     * @return _nav               NAV of the strategy
     */
    function getNAV(
        address _data,
        IGarden _garden,
        address _integration
    ) external view override returns (uint256) {
        if (!IStrategy(msg.sender).isStrategyActive()) {
            return 0;
        }
        address vaultAsset = IPassiveIntegration(_integration).getInvestmentAsset(_data);
        uint256 price = _getPrice(_garden.reserveAsset(), vaultAsset);
        uint256 NAV =
            IPassiveIntegration(_integration).getPricePerShare(_data).mul(IERC20(_data).balanceOf(msg.sender)).div(
                price
            );
        require(NAV != 0, 'NAV has to be bigger 0');
        return NAV;
    }
}
