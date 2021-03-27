/*
    Copyright 2020 Babylon Finance.

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

import 'hardhat/console.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {Initializable} from '@openzeppelin/contracts/proxy/Initializable.sol';
import {AddressArrayUtils} from '../lib/AddressArrayUtils.sol';
import {Strategy} from './Strategy.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {ITradeIntegration} from '../interfaces/ITradeIntegration.sol';
import {IPriceOracle} from '../interfaces/IPriceOracle.sol';

/**
 * @title LongStrategy
 * @author Babylon Finance
 *
 * Holds the data for a long strategy
 */
contract LongStrategy is Strategy {
    using SignedSafeMath for int256;
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;
    using AddressArrayUtils for address[];
    using Address for address;

    address sendToken;          // Asset to exchange
    address receiveToken;       // Asset to receive
    uint256 sentTokenQuantity;  // Quantity of send token to sell
    uint256 minReceiveQuantity; // Min quantity of receive token to receive

    /**
     * Enters the long strategy
     *
     */
    function _enterStrategy(
    )
        internal
        override
    {

    }

    /**
     * Exits the long strategy. Virtual method.
     * Needs to be overriden in base class.
     *
     */
    function _exitStrategy()
        internal
        override
    {

    }

}
