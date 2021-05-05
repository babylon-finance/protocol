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

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IOperation} from '../../interfaces/IOperation.sol';
import {ITradeIntegration} from '../../interfaces/ITradeIntegration.sol';
import {IPriceOracle} from '../../interfaces/IPriceOracle.sol';
import {IBabController} from '../../interfaces/IBabController.sol';

/**
 * @title LongStrategy
 * @author Babylon Finance
 *
 * Holds the data for a long strategy
 */
abstract contract Operation is IOperation {
    using SafeMath for uint256;
    /* ============ Modifiers ============ */

    modifier onlyStrategy() {
        IStrategy strategy = IStrategy(msg.sender);
        IGarden garden = strategy.garden();
        require(IBabController(controller).isSystemContract(address(garden)), 'Only a garden can call this');
        require(garden.isStrategy(msg.sender) || garden.isFinalizedStrategy(msg.sender), 'Sender must be a strategy');
        _;
    }

    /* ============ State Variables ============ */
    uint256 internal constant SLIPPAGE_ALLOWED = 1e16; // 1%
    uint256 internal constant HUNDRED_PERCENT = 1e18; // 100%
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Address of the controller
    address public controller;
    // Name of the operation
    string public name;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, address _controller) {
        require(_controller != address(0), 'Controller must be defined');
        name = _name;
        controller = _controller;
    }

    /* ============ Virtual External Functions ============ */

    function validateOperation(
        address _data,
        IGarden _garden,
        address _integration,
        uint256 _index
    ) external view virtual override;

    function executeOperation(
        address _asset,
        uint256 _capital,
        uint8 _assetStatus,
        address _data,
        IGarden _garden,
        address _integration
    )
        external
        virtual
        override
        returns (
            address,
            uint256,
            uint8
        );

    function exitOperation(
        uint256 _percentage,
        address _data,
        IGarden _garden,
        address _integration
    ) external virtual override;

    function getNAV(
        address _data,
        IGarden _garden,
        address _integration
    ) external view virtual override returns (uint256);

    /* ============ External Functions ============ */

    /**
     * Returns the name of the operation
     */
    function getName() external view override returns (string memory) {
        return name;
    }

    /**
     * Returns the price of the pair through the price oracle
     */
    function _getPrice(address _assetOne, address _assetTwo) internal view returns (uint256) {
        IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
        return oracle.getPrice(_assetOne, _assetTwo);
    }

    function _normalizeDecimals(address _asset, uint256 _quantity) internal view returns (uint256) {
        uint8 tokenDecimals = ERC20(_asset).decimals();
        return tokenDecimals != 18 ? _quantity.mul(10**(18 - tokenDecimals)) : _quantity;
    }
}
