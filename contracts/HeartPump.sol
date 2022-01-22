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

import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
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
 * @title HeartPump
 * @author Babylon Finance
 *
 * Contract that assists The Heart of Babylon garden with the locking of BABL.
 *
 */
contract HeartPump is OwnableUpgradeable {
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;
    using SafeCast for int256;
    using SafeCast for uint256;
    using SignedSafeMath for int256;
    using SafeMath for uint256;

    /* ============ Modifiers ============ */

    modifier onlyGovernanceOrEmergency {
        require(msg.sender == owner() || msg.sender == controller.EMERGENCY_OWNER(), 'Not enough privileges');
        _;
    }

    /* ============ State Variables ============ */

    // Instance of the Controller contract
    IBabController public controller;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint8 private constant BABYLON_FUSE_POOL_ID = 144;

    /* Assets that are wanted by the heart pump */
    address[] public wantedAssets;

    /* ============ Initializer ============ */

    /**
     * Set state variables and map asset pairs to their oracles
     *
     * @param _controller             Address of controller contract
     */
    function initialize(IBabController _controller, address[] calldata _wantedAssets) public {
        OwnableUpgradeable.__Ownable_init();
        require(address(_controller) != address(0), 'Incorrect address');
        controller = _controller;
        setWantedAssets(_wantedAssets);
    }

    /* ============ External Functions ============ */
    function setWantedAssets(address[] calldata _wantedAssets) public onlyGovernanceOrEmergency {
        delete wantedAssets;
        for (uint256 i = 0; i < _wantedAssets.length; i++) {
            wantedAssets.push(_wantedAssets[i]);
        }
    }
}
