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
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';

import {IBabController} from './interfaces/IBabController.sol';
import {IGarden} from './interfaces/IGarden.sol';
import {IStrategy} from './interfaces/IStrategy.sol';
import {IPriceOracle} from './interfaces/IPriceOracle.sol';
import {PreciseUnitMath} from './lib/PreciseUnitMath.sol';
import {LowGasSafeMath as SafeMath} from './lib/LowGasSafeMath.sol';

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
     * @param _garden               Garden instance to get valuation
     * @param _quoteAsset           Quote asset for the valuation
     *
     * @return                 Token valuation in terms of quote asset in precise units 1e18
     */
    function calculateGardenValuation(address _garden, address _quoteAsset) external view returns (uint256) {
        IPriceOracle priceOracle = IPriceOracle(IBabController(controller).priceOracle());
        address reserveAsset = IGarden(_garden).reserveAsset();
        uint256 totalSupply = ERC20(_garden).totalSupply();
        // If there are no tokens return 0
        if (totalSupply == 0) {
            return 0;
        }

        // uint8 reserveAssetDecimals = ERC20(reserveAsset).decimals();
        uint8 quoteAssetDecimals = ERC20(_quoteAsset).decimals();

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

        // Add garden reserve assets and garden's reserve asset.
        // TODO: Probably a bug. Gardens have some reserves such as rewards.
        valuation = valuation.add(ERC20(reserveAsset).balanceOf(address(_garden)));

        // Get the valuation in terms of the quote asset
        valuation = valuation.preciseMul(reservePrice);

        // Adds ETH of garden in _quoteAsset prices
        valuation = valuation.add(address(_garden).balance.preciseMul(wethPrice));

        if (quoteAssetDecimals < 18) {
            valuation = valuation.mul(10**(18 - quoteAssetDecimals));
        }

        return valuation.preciseDiv(ERC20(_garden).totalSupply());
    }
}
