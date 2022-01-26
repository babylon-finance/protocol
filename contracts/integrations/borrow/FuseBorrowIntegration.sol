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

pragma solidity >=0.7.0 <0.9.0;

import {IComptroller} from '../../interfaces/external/compound/IComptroller.sol';
import {ICToken} from '../../interfaces/external/compound/ICToken.sol';
import {IBabController} from '../../interfaces/IBabController.sol';

import {CompoundBorrowIntegration} from './CompoundBorrowIntegration.sol';

/**
 * @title FuseBorrowIntegration
 * @author Babylon Finance
 *
 * Class that houses fuse borrowing logic.
 */
contract FuseBorrowIntegration is CompoundBorrowIntegration {
    /* ============ State Variables ============ */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller             Address of the controller
     * @param _maxCollateralFactor    Max collateral factor allowed
     * @param _comptroller            Address of the fuse pool comptroller
     */
    constructor(
        IBabController _controller,
        uint256 _maxCollateralFactor,
        address _comptroller
    ) CompoundBorrowIntegration('fuseborrow', _controller, _maxCollateralFactor, _comptroller) {}

}
