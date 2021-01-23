/*
    Copyright 2020 DFolio

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

pragma solidity 0.7.4;

import "hardhat/console.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AddressArrayUtils } from "./lib/AddressArrayUtils.sol";
import { PreciseUnitMath } from "./lib/PreciseUnitMath.sol";
import { IFolioController } from "./interfaces/IFolioController.sol";
import { IUniswapAnchoredView } from "./interfaces/IUniswapAnchoredView.sol";
import { IOracleAdapter } from "./interfaces/IOracleAdapter.sol";


/**
 * @title PriceOracle
 * @author DFolio
 *
 * Contract that returns the price for any given asset pair. Price is retrieved either directly from an oracle,
 * calculated using common asset pairs, or uses external data to calculate price.
 * Note: Prices are returned in preciseUnits (i.e. 18 decimals of precision)
 */
contract PriceOracle is Ownable {
    using PreciseUnitMath for uint256;
    using AddressArrayUtils for address[];

    /* ============ Events ============ */

    event AdapterAdded(address _adapter);
    event AdapterRemoved(address _adapter);

    /* ============ State Variables ============ */

    // Address of the Controller contract
    IFolioController public controller;

    address immutable weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public masterQuoteAsset = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Address of uniswap anchored view contract. See https://compound.finance/docs/prices#price
    address public uniswapAnchoredView;

    // List of IOracleAdapters used to return prices of third party protocols (e.g. Uniswap, Compound, Balancer)
    address[] public adapters;

    /* ============ Constructor ============ */

    /**
     * Set state variables and map asset pairs to their oracles
     *
     * @param _controller                   Address of controller contract
     * @param _uniswapAnchoredView          Address of the uniswap anchored view that compound maintains
     * @param _adapters                     List of adapters used to price assets created by other protocols
     */
    constructor(
      IFolioController _controller,
      address _uniswapAnchoredView,
      address[] memory _adapters
    ) {
        controller = _controller;
        uniswapAnchoredView = _uniswapAnchoredView;
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
    function getPrice(address _assetOne, address _assetTwo) external view returns (uint256) {
        require(
          controller.isSystemContract(msg.sender),
          "PriceOracle.getPrice: Caller must be system contract."
        );
        // Same asset. Returns base unit
        if (_assetOne == _assetTwo) {
          return 10 ** 18;
        }

        bool priceFound;
        uint256 price;

        (priceFound, price) = _getPriceFromUniswapAnchoredView(_assetOne, _assetTwo);
        if (!priceFound) {
            (priceFound, price) = _getPriceFromAdapters(_assetOne, _assetTwo);
        }

        require(priceFound, "PriceOracle.getPrice: Price not found.");
        return price;
    }

    /**
     * GOVERNANCE FUNCTION: Add new oracle adapter.
     *
     * @param _adapter         Address of new adapter
     */
    function addAdapter(address _adapter) external onlyOwner {
        require(
            !adapters.contains(_adapter),
            "PriceOracle.addAdapter: Adapter already exists."
        );
        adapters.push(_adapter);

        emit AdapterAdded(_adapter);
    }

    /**
     * GOVERNANCE FUNCTION: Remove oracle adapter.
     *
     * @param _adapter         Address of  adapter to remove
     */
    function removeAdapter(address _adapter) external onlyOwner {
        require(
            adapters.contains(_adapter),
            "PriceOracle.removeAdapter: Adapter does not exist."
        );
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

    /* ============ Internal Functions ============ */

    /**
     * Try to calculate asset pair price by getting each asset in the pair's price relative to USD.
     * Both prices must exist otherwise function returns false and no price.
     *
     * @param _assetOne         Address of first asset in pair
     * @param _assetTwo         Address of second asset in pair
     * @return bool             Boolean indicating if oracle exists
     * @return uint256          Price of asset pair to 18 decimal precision (if exists, otherwise 0)
     */
    function _getPriceFromUniswapAnchoredView(
        address _assetOne,
        address _assetTwo
    )
        internal
        view
        returns (bool, uint256)
    {
      string memory symbol1 = _assetOne == weth ? 'ETH' : ERC20(_assetOne).symbol();
      string memory symbol2 = _assetTwo == weth ? 'ETH' : ERC20(_assetTwo).symbol();

      uint256 assetOnePrice = IUniswapAnchoredView(uniswapAnchoredView).price(symbol1);
      uint256 assetTwoPrice = IUniswapAnchoredView(uniswapAnchoredView).price(symbol2);

      if (assetOnePrice > 0 && assetTwoPrice > 0) {
        return (true, assetOnePrice.preciseDiv(assetTwoPrice));
      }

      return (false, 0);
    }

    /**
     * Scan adapters to see if one or more of the assets needs external protocol data to be priced. If
     * does not exist return false and no price.
     *
     * @param _assetOne         Address of first asset in pair
     * @param _assetTwo         Address of second asset in pair
     * @return bool             Boolean indicating if oracle exists
     * @return uint256          Price of asset pair to 18 decimal precision (if exists, otherwise 0)
     */
    function _getPriceFromAdapters(
      address _assetOne,
      address _assetTwo
    )
      internal
      view
      returns (bool, uint256)
    {
      for (uint256 i = 0; i < adapters.length; i++) {
        (
            bool priceFound,
            uint256 price
        ) = IOracleAdapter(adapters[i]).getPrice(_assetOne, _assetTwo);

        if (priceFound) {
            return (priceFound, price);
        }
      }

      return (false, 0);
    }
}
