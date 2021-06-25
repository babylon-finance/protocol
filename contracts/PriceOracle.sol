/*
    Copyright 2021 Babylon Finance

    Modified from (Set Protocol SetValuer)

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
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import {AddressArrayUtils} from './lib/AddressArrayUtils.sol';
import {PreciseUnitMath} from './lib/PreciseUnitMath.sol';

import {IBabController} from './interfaces/IBabController.sol';
import {IUniswapAnchoredView} from './interfaces/external/compound/IUniswapAnchoredView.sol';
import {IOracleAdapter} from './interfaces/IOracleAdapter.sol';
import {IPriceOracle} from './interfaces/IPriceOracle.sol';

/**
 * @title PriceOracle
 * @author Babylon Finance
 *
 * Contract that returns the price for any given asset pair. Price is retrieved either directly from an oracle,
 * calculated using common asset pairs, or uses external data to calculate price.
 * Note: Prices are returned in preciseUnits (i.e. 18 decimals of precision)
 */
contract PriceOracle is Ownable, IPriceOracle {
    using PreciseUnitMath for uint256;
    using AddressArrayUtils for address[];

    /* ============ Events ============ */

    event AdapterAdded(address _adapter);
    event AdapterRemoved(address _adapter);

    /* ============ State Variables ============ */

    // Address of the Controller contract
    IBabController public controller;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    mapping(address => bool) public uniswapAssets;

    // List of IOracleAdapters used to return prices of third party protocols (e.g. Uniswap, Compound, Balancer)
    address[] public adapters;

    /* ============ Constructor ============ */

    /**
     * Set state variables and map asset pairs to their oracles
     *
     * @param _controller                   Address of controller contract
     * @param _adapters                     List of adapters used to price assets created by other protocols
     */
    constructor(
        IBabController _controller,
        address[] memory _adapters
    ) {
        controller = _controller;
        adapters = _adapters;
    }

    /* ============ External Functions ============ */

    /**
     * SYSTEM-ONLY PRIVELEGE: Find price of passed asset pair, if possible. The steps it takes are:
     *  1) Check to see if a direct or inverse oracle of the pair exists,
     *  2) If not, use masterQuoteAsset to link pairs together (i.e. BTC/ETH and ETH/USDC
     *     could be used to calculate BTC/USDC).
     *  3) If not, check oracle adapters in case one or more of the assets needs external protocol data
     *     to price.
     *  4) If all steps fail, revert.
     *
     * @param _assetOne         Address of first asset in pair
     * @param _assetTwo         Address of second asset in pair
     * @return                  Price of asset pair to 18 decimals of precision
     */
    function getPrice(address _assetOne, address _assetTwo) external view override returns (uint256) {
        require(controller.isSystemContract(msg.sender) || msg.sender == owner(), 'Caller must be system contract');
        // Same asset. Returns base unit
        if (_assetOne == _assetTwo) {
            return 10**ERC20(_assetOne).decimals();
        }

        bool priceFound;
        uint256 price;

        (priceFound, price) = _getPriceFromAdapters(_assetOne, _assetTwo);
        require(priceFound, 'Price not found');
        return price;
    }

    /**
     * GOVERNANCE FUNCTION: Add new oracle adapter.
     *
     * @param _adapter         Address of new adapter
     */
    function addAdapter(address _adapter) external onlyOwner {
        require(!adapters.contains(_adapter), 'Adapter already exists');
        adapters.push(_adapter);

        emit AdapterAdded(_adapter);
    }

    /**
     * GOVERNANCE FUNCTION: Remove oracle adapter.
     *
     * @param _adapter         Address of  adapter to remove
     */
    function removeAdapter(address _adapter) external onlyOwner {
        adapters = adapters.remove(_adapter);

        emit AdapterRemoved(_adapter);
    }

    /* ============ External View Functions ============ */

    /**
     * Returns an array of adapters
     */
    function getAdapters() external view returns (address[] memory) {
        return adapters;
    }

    /**
     * Calls the update function in every adapter.
     * e.g Uniswap TWAP
     * @param _assetOne       First Asset of the pair
     * @param _assetTwo       Second Asset of the pair
     */
    function updateAdapters(address _assetOne, address _assetTwo) external override {
        for (uint256 i = 0; i < adapters.length; i += 1) {
            IOracleAdapter(adapters[i]).update(_assetOne, _assetTwo);
        }
    }

    /* ============ Internal Functions ============ */

    /**
     * Scan adapters to see if one or more of the assets needs external protocol data to be priced. If
     * does not exist return false and no price.
     *
     * @param _assetOne         Address of first asset in pair
     * @param _assetTwo         Address of second asset in pair
     * @return bool             Boolean indicating if oracle exists
     * @return uint256          Price of asset pair to 18 decimal precision (if exists, otherwise 0)
     */
    function _getPriceFromAdapters(address _assetOne, address _assetTwo) internal view returns (bool, uint256) {
        for (uint256 i = 0; i < adapters.length; i++) {
            (bool priceFound, uint256 price) = IOracleAdapter(adapters[i]).getPrice(_assetOne, _assetTwo);

            if (priceFound) {
                return (priceFound, price);
            }
        }

        return (false, 0);
    }
}
