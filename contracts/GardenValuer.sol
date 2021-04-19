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

pragma solidity 0.7.4;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
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
 * Contract that returns the valuation of a Garden using price oracle data used in contracts
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

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

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
     * Gets the valuation of a Garden using data from the price oracle.
     * Adds all the active strategies plus the reserve asset and ETH.
     * Note: this works for external
     * positions and negative (debt) positions.
     *
     * Note: There is a risk that the valuation is off if airdrops aren't retrieved
     *
     * @param _garden          Garden instance to get valuation
     *
     * @return                 Token valuation in terms of quote asset in precise units 1e18
     */
    function calculateGardenValuation(address _garden, address _quoteAsset) external view returns (uint256) {
        IPriceOracle priceOracle = IPriceOracle(IBabController(controller).priceOracle());
        address reserveAsset = IGarden(_garden).reserveAsset();

        uint256 reservePrice;
        // Get price of the reserveAsset in _quoteAsset
        if (reserveAsset == _quoteAsset) {
            // meaning 1 reserveAsset equals to 1 _quoteAsset
            reservePrice = 1 ether;
        } else {
            reservePrice = priceOracle.getPrice(reserveAsset, _quoteAsset);
        }

        uint256 wethPrice;
        // Get price of the WETH in _quoteAsset
        if (_quoteAsset == WETH) {
            // meaning 1 WETH equals to 1 _quoteAsset
            // this line looks ironic. 10/10.
            wethPrice = 1 ether;
        } else {
            wethPrice = priceOracle.getPrice(WETH, _quoteAsset);
        }

        address[] memory strategies = IGarden(_garden).getStrategies();
        uint256 valuation;
        for (uint256 j = 0; j < strategies.length; j++) {
            IStrategy strategy = IStrategy(strategies[j]);
            // strategies return their valuation in garden's reserveAsset
            valuation = valuation.add(strategy.getNAV());
        }

        // Recalculate the valuation in the _quoteAsset prices
        valuation = valuation.preciseMul(reservePrice);

        // Add garden's reserve asset to calculations
        valuation = valuation.add(IERC20(reserveAsset).balanceOf(address(_garden)).preciseMul(reservePrice));

        // Adds ETH of garden in _quoteAsset prices
        valuation = valuation.add(address(_garden).balance.preciseMul(wethPrice));

        return valuation.preciseDiv(IERC20(_garden).totalSupply());
    }

    /**
     * Returns the losses of a garden since a timestamp
     *
     * @param _garden                       Addres of the garden
     * @param _since                        Timestamp since when we should calculate the losses
     * @return  uint256                     Losses of a garden since a timestamp
     */
    function getLossesGarden(address _garden, uint256 _since) external view returns (uint256) {
        uint256 totalLosses = 0;
        address[] memory finalizedStrategies = IGarden(_garden).getFinalizedStrategies();
        for (uint256 i = 0; i < finalizedStrategies.length; i++) {
            if (IStrategy(finalizedStrategies[i]).executedAt() >= _since) {
                totalLosses = totalLosses.add(IStrategy(finalizedStrategies[i]).getLossesStrategy());
            }
        }
        address[] memory strategies = IGarden(_garden).getStrategies();
        for (uint256 i = 0; i < strategies.length; i++) {
            if (IStrategy(strategies[i]).executedAt() >= _since) {
                totalLosses = totalLosses.add(IStrategy(strategies[i]).getLossesStrategy());
            }
        }

        return totalLosses;
    }
}
