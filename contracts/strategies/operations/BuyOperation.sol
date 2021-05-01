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
import {Operation} from './Operation.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {ITradeIntegration} from '../../interfaces/ITradeIntegration.sol';

/**
 * @title BuyOperation
 * @author Babylon Finance
 *
 * Executes a buy operation
 */
contract BuyOperation is Operation {
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
     * Sets operation data for the buy operation
     *
     * @param _data                   Operation data
     */
    function validateOperation(
        bytes32 _data,
        IGarden _garden,
        IStrategy _strategy,
        address _integration
    ) external view override onlyStrategy {
        require(getParsedData(_data) != _garden.reserveAsset(), 'Receive token must be different');
    }

    /**
     * Executes the buy operation
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
        address longToken = getParsedData(_data);
        IStrategy(_strategy).trade(_asset, _capital, longToken);
        return (longToken, IERC20(longToken).balanceOf(address(msg.sender)));
    }

    /**
     * Exits the buy operation.
     * @param _percentage of capital to exit from the strategy
     */
    function exitOperation(
        uint256 _percentage,
        bytes32 _data,
        IGarden _garden,
        IStrategy _strategy,
        address _integration
    ) external override onlyStrategy {
        require(_percentage <= 100e18, 'Unwind Percentage <= 100%');
        address longToken = getParsedData(_data);
        IStrategy(_strategy).trade(
            longToken,
            IERC20(longToken).balanceOf(address(msg.sender)).preciseMul(_percentage),
            _garden.reserveAsset()
        );
    }

    /**
     * Gets the NAV of the buy op in the reserve asset
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
        address longToken = getParsedData(_data);
        uint256 price = _getPrice(_garden.reserveAsset(), longToken);
        uint256 NAV = IERC20(longToken).balanceOf(msg.sender).preciseDiv(price);
        require(NAV != 0, 'NAV has to be bigger 0');
        return NAV;
    }

    /* ============ Private Functions ============ */

    function getParsedData(bytes32 _data) private view returns (address) {
        return _convertDataToAddress(_data);
    }
}
