/*
    Copyright 2020 Babylon Finance

    Modified from (Set Protocol GardenValuer)

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
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';

import {IBabController} from './interfaces/IBabController.sol';
import {IGarden} from './interfaces/IGarden.sol';
import {IStrategy} from './interfaces/IStrategy.sol';
import {IPriceOracle} from './interfaces/IPriceOracle.sol';
import {PreciseUnitMath} from './lib/PreciseUnitMath.sol';

/**
 * @title GardenValuer
 * @author Babylon Finance
 *
 * Contract that returns the valuation of SetTokens using price oracle data used in contracts
 * that are external to the system.
 *
 * Note: Prices are returned in preciseUnits (i.e. 18 decimals of precision)
 */
contract GardenValuer {
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;
    using SafeCast for int256;
    using SafeCast for uint256;
    using SignedSafeMath for int256;
    using SafeMath for uint256;

    /* ============ State Variables ============ */

    // Instance of the Controller contract
    address public controller;

    /* ============ Constructor ============ */

    /**
     * Set state variables and map asset pairs to their oracles
     *
     * @param _controller             Address of controller contract
     */
    constructor(address _controller) {
        controller = _controller;
    }

    /* ============ External Functions ============ */

    /**
     * Gets the valuation of a Garden using data from the price oracle. Reverts
     * if no price exists for a component in the Garden. Note: this works for external
     * positions and negative (debt) positions.
     *
     * Note: There is a risk that the valuation is off if airdrops aren't retrieved or
     * debt builds up via interest and its not reflected in the position
     *
     * @param _garden       Garden instance to get valuation
     * @param _quoteAsset      Address of token to quote valuation in
     *
     * @return                 Token valuation in terms of quote asset in precise units 1e18
     */
    function calculateGardenValuation(IGarden _garden, address _quoteAsset) external view returns (uint256) {
        IPriceOracle priceOracle = IPriceOracle(IBabController(controller).getPriceOracle());

        // NOTE: This is temporary to allow for deposits / withdrawls. The masterQuoetAsset no longer
        // live in the PriceOracle so we'll need to add it back or take another approach.
        address masterQuoteAsset = priceOracle.masterQuoteAsset();

        address[] memory strategies = _garden.getStrategies();
        int256 valuation;
        for (uint256 j = 0; j < strategies.length; j++) {
            IStrategy strategy = IStrategy(strategies[j]);
            address[] memory positions = strategy.getPositions();

            for (uint256 i = 0; i < positions.length; i++) {
                address component = positions[i];

                // Get component price from price oracle. If price does not exist, revert.
                uint256 componentPrice = priceOracle.getPrice(component, masterQuoteAsset);
                int256 aggregateUnits = strategy.getPositionBalance(component);
                // Normalize each position unit to preciseUnits 1e18 and cast to signed int
                uint8 unitDecimals = ERC20(component).decimals();
                uint256 baseUnits = 10**unitDecimals;

                int256 normalizedUnits = aggregateUnits.preciseDiv(baseUnits.toInt256());
                // Calculate valuation of the component. Debt positions are effectively subtracted
                valuation = normalizedUnits.preciseMul(componentPrice.toInt256()).add(valuation);
            }
        }

        if (masterQuoteAsset != _quoteAsset && valuation > 0) {
            uint256 quoteToMaster = priceOracle.getPrice(_quoteAsset, masterQuoteAsset);
            valuation = valuation.preciseDiv(quoteToMaster.toInt256());
        }
        // Get component price from price oracle. If price does not exist, revert.
        uint256 reservePrice = priceOracle.getPrice(_garden.getReserveAsset(), masterQuoteAsset);
        valuation = valuation.add(
            ERC20(_garden.getReserveAsset()).balanceOf(address(_garden)).toInt256().preciseMul(reservePrice.toInt256())
        );
        // Adds ETH set aside
        valuation = valuation.add(address(_garden).balance.toInt256());
        return valuation.toUint256().preciseDiv(_garden.totalSupply());
    }
}
