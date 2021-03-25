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

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {Math} from '../lib/Math.sol';

import {TimeLockedToken} from './TimeLockedToken.sol';
import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';

//import "./Proxy.sol";
//import "./interfaces/ISynthetix.sol";
//import "./interfaces/IERC20.sol";

contract RewardsSupplySchedule is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;
    using SafeDecimalMath for uint256;
    using Math for uint256;
    using Math for uint256;

    /* ============ State Variables ============ */

    // The initial quarterly supply in Quarter 1 (Q1) is 53_571
    //uint public constant INITIAL_QUARTERLY_SUPPLY = 53_571_430e15; // 53_571e18 for first quarter

    // Max BABL rewards for mining 500_000e18
    uint256 public constant MAX_REWARD = 500_000e18;

    uint256 public constant Q1_REWARDS = 53_571_428_571_428_600e6;

    // Quarterly percentage decay of inflationary supply
    uint256 public constant DECAY_RATE = 120000000000000000; // 12% quarterly (each 90 days) (Rewards on Q1 = 1,12 * Rewards on Q2) Q1= Quarter 1, Q2 = Quarter 2

    constructor() //TimeLockedToken _token,
    //IRewardsDistributor _rewardsDistributor,
    //uint _lastMintEvent,
    //uint _currentQuarter
    {
        //lastMintEvent = _lastMintEvent;
        //quarterCounter = _currentQuarter;
        //token = _token;
        //rewardsDistributor = _rewardsDistributor;
    }

    function tokenSupplyPerQuarter(uint256 quarter) public pure returns (uint256) {
        require(quarter >= 1, 'RewardsSupplySchedule::tokenSupplyPerQuarter: There are only 1 or more quarters');
        require(quarter < 513, 'RewardsSupplySchedule::tokenSupplyPerQuarter: overflow');

        uint256 firstFactor = (SafeDecimalMath.unit().add(DECAY_RATE)).powDecimal(quarter.sub(1));
        uint256 supplyForQuarter = Q1_REWARDS.divideDecimal(firstFactor);

        return supplyForQuarter;
    }
}
