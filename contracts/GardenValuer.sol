// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.9;
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';

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
        require(_controller != address(0), 'Incorrect address');
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
        require(
            address(priceOracle) != address(0) &&
                _garden != address(0) &&
                _quoteAsset != address(0) &&
                IBabController(controller).isSystemContract(_garden),
            'Incorrect input data'
        );
        address reserveAsset = IGarden(_garden).reserveAsset();
        uint256 totalSupply = ERC20(_garden).totalSupply();
        // If there are no tokens return 0
        if (totalSupply == 0) {
            return 0;
        }
        uint8 quoteAssetDecimals = ERC20(_quoteAsset).decimals();

        uint256 reservePrice;
        // Get price of the reserveAsset in _quoteAsset
        if (reserveAsset == _quoteAsset) {
            // meaning 1 reserveAsset equals to 1 _quoteAsset
            reservePrice = 1 ether;
        } else {
            reservePrice = priceOracle.getPrice(reserveAsset, _quoteAsset);
        }

        address[] memory strategies = IGarden(_garden).getStrategies();
        uint256 valuation;
        for (uint256 j = 0; j < strategies.length; j++) {
            IStrategy strategy = IStrategy(strategies[j]);
            // strategies return their valuation in garden's reserveAsset
            valuation = valuation+(strategy.getNAV());
        }

        // Add garden reserve assets and garden's reserve asset
        valuation = valuation+(ERC20(reserveAsset).balanceOf(address(_garden)));

        // Subtract the reserves set aside for rewards
        valuation = valuation-(IGarden(_garden).reserveAssetRewardsSetAside());

        // Subtract Keeper debt
        valuation = valuation-(IGarden(_garden).keeperDebt());

        // Get the valuation in terms of the quote asset
        valuation = valuation.preciseMul(reservePrice);

        if (quoteAssetDecimals < 18) {
            valuation = valuation*(10**(18 - quoteAssetDecimals));
        }

        return valuation.preciseDiv(ERC20(_garden).totalSupply());
    }
}
