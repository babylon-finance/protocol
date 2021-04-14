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

pragma solidity 0.7.4;

import 'hardhat/console.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {Strategy} from './Strategy.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IPassiveIntegration} from '../interfaces/IPassiveIntegration.sol';

/**
 * @title YieldFarmingStrategy
 * @author Babylon Finance
 *
 * Holds the data for a long strategy
 */
contract YieldFarmingStrategy is Strategy {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;

    address public yieldVault; // Yield Farming Vault
    address public vaultAsset; // Vault Asset required

    /**
     * Sets integration data for the long strategy
     *
     * @param _yieldVault                   Yield vault to enter
     */
    function setData(address _yieldVault) external onlyGardenAndNotSet {
        require(IPassiveIntegration(integration).isInvestment(_yieldVault), 'Must be a valid yield vault');

        kind = 2;
        yieldVault = _yieldVault;
        vaultAsset = IPassiveIntegration(integration).getInvestmentAsset(_yieldVault);
        dataSet = true;
    }

    /**
     * Gets the NAV of the liquidity pool asset in ETH
     *
     * @return _nav           NAV of the strategy
     */
    function getNAV() public view override returns (uint256) {
        if (!active || finalized) {
            return 0;
        }
        uint256 price = _getPrice(garden.reserveAsset(), vaultAsset);
        return
            IPassiveIntegration(integration)
                .getPricePerShare(yieldVault)
                .mul(IERC20(yieldVault).balanceOf(address(this)))
                .div(price);
    }

    /**
     * Enters the long strategy
     */
    function _enterStrategy(uint256 _capital) internal override {
        if (vaultAsset != garden.reserveAsset()) {
            _trade(garden.reserveAsset(), _capital, vaultAsset);
        }
        uint256 exactAmount = IPassiveIntegration(integration).getExpectedShares(yieldVault, _capital);
        uint256 minAmountExpected = exactAmount.sub(exactAmount.preciseMul(SLIPPAGE_ALLOWED));
        IPassiveIntegration(integration).enterInvestment(
            yieldVault,
            minAmountExpected,
            vaultAsset,
            IERC20(vaultAsset).balanceOf(address(this))
        );
    }

    /**
     * Exits the yield farming strategy.
     * @param _percentage of capital to exit from the strategy
     */
    function _exitStrategy(uint256 _percentage) internal override {
        require(_percentage <= HUNDRED_PERCENT, 'Unwind Percentage <= 100%');
        uint256 amountVault = IERC20(yieldVault).balanceOf(address(this)).preciseMul(_percentage);
        IPassiveIntegration(integration).exitInvestment(
            yieldVault,
            amountVault,
            vaultAsset,
            IPassiveIntegration(integration).getPricePerShare(yieldVault).mul(
                amountVault.sub(amountVault.preciseMul(SLIPPAGE_ALLOWED))
            )
        );
        if (vaultAsset != garden.reserveAsset()) {
            _trade(vaultAsset, IERC20(vaultAsset).balanceOf(address(this)), garden.reserveAsset());
        }
    }
}
