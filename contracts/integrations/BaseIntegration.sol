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
import {IBabController} from '../interfaces/IBabController.sol';
import {IIntegration} from '../interfaces/IIntegration.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';

/**
 * @title BaseIntegration
 * @author Babylon Finance
 *
 * Abstract class that houses common Integration-related state and functions.
 */
abstract contract BaseIntegration {
    using SafeCast for int256;
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for uint256;

    /* ============ Modifiers ============ */

    modifier onlySystemContract() {
        require(IBabController(controller).isSystemContract(msg.sender), 'Only system can call this');
        _;
    }

    /* ============ State Variables ============ */

    uint256 internal constant SLIPPAGE_ALLOWED = 1e16; // 1%

    // Address of the controller
    address public controller;
    // Wrapped ETH address
    address public immutable weth;
    // Name of the integration
    string public name;
    mapping(address => bool) public initializedByGarden;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     */

    constructor(
        string memory _name,
        address _weth,
        address _controller
    ) {
        require(_controller != address(0), 'Controller must be defined');
        name = _name;
        controller = _controller;
        weth = _weth;
    }

    /* ============ External Functions ============ */

    /**
     * Returns the name of the integration
     */
    function getName() external view returns (string memory) {
        return name;
    }
}
